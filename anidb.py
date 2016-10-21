#!/usr/bin/env python3
import sys, re, socket, atexit, threading, time, os
from functools import reduce

host       = ("api.anidb.net", 9000)
port       = 1444
file_arr   = []
still_open = True

def rename_worker(path_to, path_from):
    print("~ Renaming: %s => %s" % (path_from, path_to))
    try:
        os.rename(path_from, path_to)
    except OSError as e:
        print("! ERROR! Failed to rename \"%s\" - %s" % (path_from, e))

class ED2K():
    def __init__(self, path, size, ed2k):
        self.path = path
        self.size = size
        self.hash = ed2k


class Response():
    def __init__(self, msg):
        a         = msg.split(' ')
        self.code = int(a[0])
        self.msg  = ' '.join(a[1:])


class Config():
    def __init__(self, path):
        if not os.path.exists(path):
            print("ERROR! Invalid config path")
            exit()

        self.keys = dict(x.split('=') for x in [y[:-1] for y in open(path).readlines() if not y.startswith('#') and '=' in y])
        if 'default' not in self.keys:
            self.keys['default'] = '%epno. %romanji_name - %english_name (%anime_type, %src) [%crc32] - %group_short_name.%file_type'
        if not ('pass' in self.keys and 'user' in self.keys):
            print("ERROR! Username or password not provided in config")
            exit()

        self.config_fields = list(set(re.findall(r'%([0-9a-zA-Z_]+)', "%anime_type" + ' '.join([self.keys[x] for x in ['unknown', 'TV', 'OVA', 'Movie', 'Other', 'web', 'default'] if x in self.keys]))))
        fmask              = self.make_map(['', 'aid', 'eid', 'gid', 'lid', 'list_other_episodes', '', 'state', 'size', 'ed2k', 'md5', 'sha1', 'crc32', '', '', '', 'quality', 'src', 'audio', 'audio_bitrate_list', 'video', 'video_bitrate', 'res', 'file_type', 'dub', 'sub', 'length', 'description', 'aired_date', '', '', 'anidb_file_name', 'mylist_state', 'mylist_filestate', 'mylist_viewed', 'mylist_viewdate', 'mylist_storage', 'mylist_source', 'mylist_other', ''], self.config_fields)
        amask              = self.make_map(['anime_total_episodes', 'highest_episode_number', 'year', 'anime_type', 'related_aid_list', 'related_aid_type', 'category_list', '', 'romanji_name', 'kanji_name', 'english_name', 'other_name', 'short_name_list', 'synonym_list', '', '', 'epno', 'ep_name', 'ep_romanji_name', 'ep_kanji_name', 'episode_rating', 'episode_vote_count', '', '', 'group_name', 'group_short_name', '', '', '', '', '', 'date_aid_record_updated'], self.config_fields)
        self.fmask         = fmask[0]
        self.amask         = amask[0]
        self.fields        = ['fid'] + fmask[1] + amask[1]

    def get(self, key):
        return self.keys[key] if key in self.keys else None

    def make_map(self, a, b):
        m = ''.join(['1' if x in b else '0' for x in a])
        return ('%0*X' % ((len(m) + 3) // 4, int(m, 2)),
                [a[z] for z, y in enumerate(m) if y == '1'])


class API(threading.Thread):
    def __init__(self, config):
        threading.Thread.__init__(self)
        self.config  = config
        self.timer   = int(time.time())
        self.session = ""
        try:
            self.s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            self.s.bind(('', 1444))
        except socket.error:
            print("ERROR! Socket failed")
            exit()
        self.session = self.auth()

    def run(self):
        while len(file_arr) > 0 or still_open:
            if len(file_arr) > 0:
                self.file(file_arr[0])
                file_arr.pop(0)

    def close(self):
        if len(self.session) > 0:
            self.send("LOGOUT s=%s" % self.session, True)
        self.s.close()

    def auth(self, auth_try=0):
        ret = self.send("AUTH user=%s&pass=%s&protover=3&client=aniren&clientver=3&nat=1&enc=utf-8" % (self.config.get('user'), self.config.get('pass')), not auth_try)
        if ret.code != 200:
            print("ERROR! Auth failed")
            exit()

        session = ret.msg.split(' ')[0]
        m = re.match(r'^[a-zA-Z0-9]{4,8}$', session)
        if m:
            return session
        else:
            print("ERROR! Auth failed, can't get session key")
            exit()

    def file(self, ed2k):
        ret = self.send("FILE size=%d&ed2k=%s&fmask=%s&amask=%s&s=%s" % (ed2k.size, ed2k.hash, self.config.fmask, self.config.amask, self.session))
        x   = ret.msg[5:-1].split('|')
        y   = {f: x[self.config.fields.index(f)] for f in self.config.config_fields}
        t   = threading.Thread(target=rename_worker, args=(reduce(lambda a, b: a.replace('%' + b, y[b]), y, self.config.get(y['anime_type']) if y['anime_type'] in self.config.keys else self.config.get('default')), ed2k.path))
        t.start()

    def update_timer(self):
        self.timer = int(time.time())

    def send(self, msg, skipwait=False):
        print("> ", re.sub(r'user=\w+&pass=.*?&', "user=******&pass=******&", msg))
        x = int(time.time())
        if x - self.timer < 4 and not skipwait:
            y = 4 - x + self.timer
            print("~ Waiting %d second(s)" % y)
            time.sleep(y)
        self.s.sendto(msg.encode('UTF-8'), host)
        self.update_timer()
        a = Response(self.s.recvfrom(1024)[0].decode('UTF-8'))
        print("< %d %s" % (a.code, a.msg[:-1]))
        return a

c_path = os.path.expanduser("~/.anime-ren.conf")
if not os.path.exists(c_path):
    c_path = ".anime-ren.conf"
    if not os.path.exists(c_path):
        print("ERROR! Can't find config file")
        exit()
api = API(Config(c_path))
api.start()

def at_exit():
    api.close()
atexit.register(at_exit)

for arg in sys.stdin:
    m = re.match(r'^(\/.+)+\.(.+){3,4}\|(\d+)|[A-Ga-g0-9]{32}$', arg)
    if m:
        a, b, c = arg.split('|')
        file_arr.append(ED2K(a, int(b), c[:-1]))
still_open = False
api.join()
