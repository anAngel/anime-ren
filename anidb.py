#!/usr/bin/env python3
import sys, re, socket, atexit, threading, time, os, queue
from functools import reduce

host         = ("api.anidb.net", 9000)
port         = ('', 1444)
last_request = time.time()
work_queue   = queue.Queue()
config       = {'default': '%epno. %romanji_name - %english_name (%anime_type, %src) [%crc32] - %group_short_name.%file_type'}
session_key  = ''
session      = None
loading_anim = False
loading_x    = 1

config_path = os.path.expanduser("~/.anime-ren.conf")
if not os.path.exists(config_path):
    config_path = ".anime-ren.conf"
    if not os.path.exists(config_path):
        print("! ERROR! Can't find config file")
        exit()

try:
    config = {**config, **dict(x.split('=') for x in [y[:-1] for y in open(config_path).readlines() if not y.startswith('#') and '=' in y])}
except OSError as e:
    print("! ERROR! Failed to open config file: \"%s\"" % config_path, end="\n\n")
    raise

if not ('pass' in config and 'user' in config):
    print("! ERROR! No username or password in config!")
    exit()

def make_map(a, b):
    m = ''.join(['1' if x in b else '0' for x in a])
    return ('%0*X' % ((len(m) + 3) // 4, int(m, 2)),
            [a[z] for z, y in enumerate(m) if y == '1'])

config_fields   = list(set(re.findall(r'%([0-9a-zA-Z_]+)', "%anime_type" + ' '.join([config[x] for x in ['unknown', 'TV', 'OVA', 'Movie', 'Other', 'web', 'default'] if x in config]))))
fmask           = make_map(['', 'aid', 'eid', 'gid', 'lid', 'list_other_episodes', '', 'state', 'size', 'ed2k', 'md5', 'sha1', 'crc32', '', '', '', 'quality', 'src', 'audio', 'audio_bitrate_list', 'video', 'video_bitrate', 'res', 'file_type', 'dub', 'sub', 'length', 'description', 'aired_date', '', '', 'anidb_file_name', 'mylist_state', 'mylist_filestate', 'mylist_viewed', 'mylist_viewdate', 'mylist_storage', 'mylist_source', 'mylist_other', ''], config_fields)
amask           = make_map(['anime_total_episodes', 'highest_episode_number', 'year', 'anime_type', 'related_aid_list', 'related_aid_type', 'category_list', '', 'romanji_name', 'kanji_name', 'english_name', 'other_name', 'short_name_list', 'synonym_list', '', '', 'epno', 'ep_name', 'ep_romanji_name', 'ep_kanji_name', 'episode_rating', 'episode_vote_count', '', '', 'group_name', 'group_short_name', '', '', '', '', '', 'date_aid_record_updated'],   config_fields)
fields          = ['fid'] + fmask[1] + amask[1]
config['fmask'] = fmask[0]
config['amask'] = amask[0]

try:
    session = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    session.bind(port)
except socket.error as e:
    print("! ERROR! Failed to create socket")
    raise

end_input    = threading.Lock()
end_input.acquire()
interrupted  = threading.Lock()
interrupted.acquire()

def work_rename(path_to, path_from):
    print("~ Renaming: %s => %s" % (path_from, path_to))
    try:
        os.rename(path_from, path_to)
    except OSError as e:
        print("! ERROR! Failed to rename \"%s\" - %s" % (path_from, e))

def send_request(cmd, skip_wait=False):
    global loading_anim
    if loading_anim:
        print(' ' * loading_x, end='\r')
        loading_anim = False

    print(">", re.sub(r'user=\w+&pass=.*?&', "user=******&pass=******&", cmd))

    global last_request
    wait = 4 - time.time() + last_request
    if wait > 0 and not skip_wait:
        print("~ Waiting %d second%s" % (wait, '' if wait == 1 else "(s)"))
        time.sleep(wait)

    session.sendto(cmd.encode('UTF-8'), host)
    last_request = time.time()

    msg = session.recvfrom(1024)[0].decode('UTF-8').split(" ")
    ret = (int(msg[0]), ' '.join(msg[1:])[:-1])
    print("< %d %s" % ret)
    if not ret[0] in [200, 203, 220, 300]:
        interrupted.release()
        exit()
    return ret

def work_loop():
    while not interrupted.acquire(blocking=False):
        try:
            x = work_queue.get(timeout=0.1)
            y = send_request("FILE size=%d&ed2k=%s&fmask=%s&amask=%s&s=%s" % (int(x[1]), x[2], config['fmask'], config['amask'], session_key))
            z = dict(zip(fields, y[1][5:].split('|')))
            t = threading.Thread(target=work_rename, args=(reduce(lambda a, b: a.replace('%' + b, z[b]), z, config[z['anime_type']] if z['anime_type'] in config else config['default']), x[0]))
            t.start()
        except queue.Empty:
            if end_input.acquire(blocking=False):
                break
            else:
                global loading_anim, loading_x
                if time.time() - last_request > 3 and not loading_anim:
                    loading_anim = True
                if loading_anim:
                    print('·' * loading_x, end='\r')
                    loading_x += 1
                    if loading_x > 6:
                        print(' ' * loading_x, end='\r')
                        loading_x = 1
                if time.time() - last_request > 300:
                    send_request("PING", True)

work_thread = threading.Thread(target=work_loop)
work_thread.start()

def work_cleanup():
    if not work_queue.empty():
        print("\n\n! Incomplete Jobs:")
        while not work_queue.empty():
            print("~ %s" % work_queue.get()[0])
        print()

tmp_key = send_request("AUTH user=%s&pass=%s&protover=3&client=aniren&clientver=3&nat=1&enc=utf-8" % (config['user'], config['pass']), True)[1].split(' ')[0]
m       = re.match(r'^[a-zA-Z0-9]{4,8}$', tmp_key)
if m:
    session_key = tmp_key
else:
    print("! ERROR! Auth failed, can't get session key")
    exit()

def at_exit():
    if len(session_key):
        send_request("LOGOUT s=%s" % session_key, True)
    session.close()
atexit.register(at_exit)

try:
    for line in sys.stdin:
        m = re.match(r'^(\/.+)+\.(.+){3,4}\|(\d+)|[A-Ga-g0-9]{32}$', line)
        if m:
            work_queue.put(line[:-1].split('|'))

    end_input.release()
    work_thread.join()
except KeyboardInterrupt:
    interrupted.release()
    work_cleanup()
