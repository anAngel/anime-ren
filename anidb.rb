#!/usr/bin/env ruby
require 'socket'

AMASK      = "B0E0F040"
FMASK      = "7178EAC0"
ED2K_BLOCK = 9728000
SERV_ADDR  = "api.anidb.net"
SERV_PORT  = 9000

API_RESP = Struct.new :code, :msg
ED2K_RET = Struct.new :hash, :fname, :len

test = "AUTH user=#{}&pass=#{}&protover=3&client=aniren&clientver=2&enc=UTF8"

sock = UDPSocket.new
sock.bind 0, SERV_PORT
sock.connect SERV_ADDR, SERV_PORT
sock.send test, 0
data, addr = sock.recvfrom(1024)
puts "From addr: '%s', msg: '%s'" % [addr.join(','), data]
sock.send "LOGOUT", 0
data, addr = sock.recvfrom(1024)
puts "From addr: '%s', msg: '%s'" % [addr.join(','), data]
sock.close

while STDIN.gets
  puts $_
end
