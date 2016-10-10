import sys, re, socket, atexit, threading, time

host = ('api.anidb.net', 9000)
port = 1444
file_arr, still_open = [], True

user, pw = open('secret', 'r').read()[:-1].split('\n')

class ED2K():
    def __init__(self, path, ed2k):
        self.path = path
        self.hash = ed2k

class Response():
    def __init__(self, msg):
        a = msg.split(" ")
        self.code = int(a[0])
        self.msg  = ' '.join(a[1:])

class Config():
    def __init__(self, path):
        return

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
                print(file_arr[0].path, file_arr[0].hash)
                file_arr.pop(0)

    def close(self):
        if len(self.session) > 0:
            self.send("LOGOUT s=%s" % self.session, True)
        self.s.close()

    def auth(self):
        ret = self.send("AUTH user=%s&pass=%s&protover=3&client=aniren&clientver=3&nat=1&enc=utf-8" % (user, pw), True)
        if ret.code == 200:
            return ret.msg.split(" ")[0]
        else:
            print("ERROR! Auth failed: %d %s" % (ret.code, ret.msg))
            exit()

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
    m = re.match(r'^(\/.+)+\.(.+){3,4}\|[A-Ga-g0-9]{32}$', arg)
    if m:
        a, b = arg.split('|')
        file_arr.append(ED2K(a, b[:-1]))
still_open = False
api.join()
