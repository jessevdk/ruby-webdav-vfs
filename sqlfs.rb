#!/usr/bin/env ruby

$:.insert(0, File.join(File.dirname(File.expand_path(__FILE__)), 'examples/sqlfs'))

require 'rubygems'
require 'webrick'
require 'examples/sqlfs/service'
require 'webdavhandler'
require 'memorylocking'

class LockedSqlFs < SqlFs::Service
	include MemoryLocking
end

log = WEBrick::Log.new
serv = WEBrick::HTTPServer.new({ 
	:Port => 1111, 
	:Logger => log, 
	:BindAddress => '192.168.1.12'
})

serv.mount("/", WEBrick::HTTPServlet::WebDAVHandler, :Root => '/', :VFS => LockedSqlFs)
trap(:INT){ serv.shutdown }
serv.start
