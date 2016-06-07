#!/usr/bin/env ruby
require 'socket'

AMASK      = "B0E0F040"
FMASK      = "7178EAC0"
ED2K_BLOCK = 9728000
SERV_ADDR  = "api.anidb.net"
SERV_PORT  = 9000

API_RESP = Struct.new :status, :msg
ED2K_RET = Struct.new :hash, :fname, :len

class API
  attr_accessor :sock

  def initialize
    @sock = UDPSocket.new
    @sock.bind 0, SERV_PORT
    @sock.connect SERV_ADDR, SERV_PORT
  end

  def exec cmd
    puts "< #{cmd}"
    @sock.send(cmd, 0)
    status, msg = @sock.recvfrom(1024)[0].split " "
    puts "> #{status}: #{msg}"
  end

  def exit
    exec("LOGOUT")
    @sock.close
    @sock = nil
  end
end
api = API.new

at_exit do
  api.exit
end

secret = File.open("secret", "rb").read.split "\n"
api.exec("AUTH user=#{secret[0]}&pass=#{secret[1]}&protover=3&client=aniren&clientver=2&enc=UTF8")

while STDIN.gets
  puts $_
end
