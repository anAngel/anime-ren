import sys, re, socket, atexit, threading, time

host = ('api.anidb.net', 9000)
port = 1444
file_arr, still_open = [], True

class ED2K():
    def __init__(self, path, ed2k):
        self.path = path
        self.hash = ed2k

class Config():
    def __init__(self, path):
        return

class API(threading.Thread):
    def __init__(self):
        threading.Thread.__init__(self)
        self.timer = int(time.time())
        try:
            self.s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            self.s.bind(('', 1444))
        except socket.error:
            print("ERROR! Socket failed")
            exit()

    def run(self):
        while len(file_arr) > 0 or still_open:
            if len(file_arr) > 0:
                print(file_arr[0].path, file_arr[0].hash)
                file_arr.pop(0)

    def exec(self, msg):
        return

api = API()
api.start()

def at_exit():
    api.s.close()
atexit.register(at_exit)

user, pw = open('secret', 'r').read()[:-1].split('\n')

for arg in sys.stdin:
    m = re.match(r'^(\/.+)+\.(.+){3,4}\|[A-Ga-g0-9]{32}$', arg)
    if m:
        a, b = arg.split('|')
        file_arr.append(ED2K(a, b[:-1]))
still_open = False
api.join()
