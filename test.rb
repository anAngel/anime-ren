#!/usr/bin/ruby

arr = []
t = Thread.new {
  sleep 1
  while arr.length > 0
    puts "#{arr.length} -- #{arr.shift}"
    sleep 1
  end
}

while STDIN.gets
  arr.push $_
  puts $_
end
t.join
