#!/usr/bin/env python3
import sys, re, socket, atexit, threading, time

host = ('api.anidb.net', 9000)
port = 1444
file_arr, still_open = [], True

fields = ['fid', 'aid', 'eid', 'gid', 'size', 'ed2k', 'md5', 'sha1', 'crc32', 'dub', 'sub', 'src', 'audio', 'video', 'res', 'file_type', 'group_short_name', 'epno', 'ep_name', 'ep_romanji_name', 'ep_kanji_name', 'year', 'anime_total_episodes', 'romanji_name', 'english_name', 'kanji_name']

class ED2K():
    def __init__(self, path, size, ed2k):
        self.path = path
        self.size = size
        self.hash = ed2k

class Response():
    def __init__(self, msg):
        a = msg.split(" ")
        self.code = int(a[0])
        self.msg  = ' '.join(a[1:])

class Config():
    def __init__(self, path):
        self.fmask = self.make_map(['unused', 'aid', 'eid', 'gid', 'mylist_id', 'list_other_episodes', 'IsDeprecated', 'state', 'size', 'ed2k', 'md5', 'sha1', 'crc32', 'unused', 'unused', 'reserved', 'quality', 'src', 'audio', 'audio_bitrate_list', 'video', 'video_bitrate', 'res', 'file_type', 'dub', 'sub', 'length_in_seconds', 'description', 'aired_date', 'unused', 'unused', 'anidb_file_name', 'mylist_state', 'mylist_filestate', 'mylist_viewed', 'mylist_viewdate', 'mylist_storage', 'mylist_source', 'mylist_other', 'unused'], fields)
        self.amask = self.make_map(['anime_total_episodes', 'highest_episode_number', 'year', 'file_type', 'related_aid_list', 'related_aid_type', 'category_list', 'reserved', 'romanji_name', 'kanji_name', 'english_name', 'other_name', 'short_name_list', 'synonym_list', 'retired', 'retired', 'epno', 'ep_name', 'ep_romanji_name', 'ep_kanji_name', 'episode_rating', 'episode_vote_count', 'unused', 'unused', 'group_name', 'group_short_name', 'unused', 'unused', 'unused', 'unused', 'unused', 'date_aid_record_updated'], fields)
        return

    def make_map(self, a, b):
        m = ''.join(['1' if x in b else '0' for x in a])
        return ('%0*X' % ((len(m) + 3) // 4, int(m, 2)),
                [a[z] for z, y in enumerate(m) if y == '1'])


class API(threading.Thread):
    def __init__(self):
        threading.Thread.__init__(self)
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

    def auth(self):
        user, pw = open('secret', 'r').read()[:-1].split('\n')
        ret = self.send("AUTH user=%s&pass=%s&protover=3&client=aniren&clientver=3&nat=1&enc=utf-8" % (user, pw), True)
        if ret.code == 200:
            return ret.msg.split(" ")[0]
        else:
            print("ERROR! Auth failed: %d %s" % (ret.code, ret.msg))
            exit()

    def file(self, ed2k):
        ret = self.send('FILE size=%d&ed2k=%s&fmask=%s&amask=%s&s=%s' % (ed2k.size, ed2k.hash, fmask, amask, self.session))
        return

    def update_timer(self):
        self.timer = int(time.time())

    def send(self, msg, skipwait=False):
        print("> ", re.sub(r'user=\w+&pass=.*?&', "user=*****&pass=*****&", msg))
        x = int(time.time())
        if x - self.timer < 4 and not skipwait:
            y = 4 - x + self.timer
            print("~ Waiting %d second(s)", y)
            time.sleep(y)
        self.s.sendto(msg.encode('UTF-8'), host)
        self.update_timer()
        a = Response(self.s.recvfrom(1024)[0].decode('UTF-8'))
        print("< %d %s" % (a.code, a.msg[:-1]))
        return a

api = API()
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
