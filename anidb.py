import sys, re, socket, atexit, threading

host = ('api.anidb.net', 9000)
port = 1444

file_arr, still_open = [], False
def worker():
    while len(file_arr) > 0 or still_open:
        continue

def at_exit():
    return


class API(threading.Thread):
    def __init__(self):
        return

t = threading.Thread(target=worker)
t.start()
atexit.register(at_exit)

for arg in sys.stdin:
    m = re.match(r'^(\/.+)+\.(.+){3,4}\|[A-Ga-g0-9]{32}$', arg)
    if m:
        a, b = arg.split('|')
        print(a, b[:-1])
t.join()
