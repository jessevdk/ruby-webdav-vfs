#!/usr/bin/env ruby

require 'rubygems'
require 'webrick'
require 'webdavhandler'
require 'memorylocking'
require 'vfs/local'

class LockedLocal < VFS::Local
	include MemoryLocking
end

log = WEBrick::Log.new
serv = WEBrick::HTTPServer.new({ 
	:Port => 10080, 
	:Logger => log, 
	:BindAddress => '192.168.1.12'
})

serv.mount("/", WEBrick::HTTPServlet::WebDAVHandler, :Root => Dir.pwd, :VFS => LockedLocal)
trap(:INT){ serv.shutdown }
serv.start
