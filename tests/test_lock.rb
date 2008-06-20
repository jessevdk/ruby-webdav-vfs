#!/usr/bin/env ruby

require 'tests/testutilities'
require 'net/http'

class LockTest < Test::Unit::TestCase
	include TestUtilities
	
	def lock_resource(resource, recursive = false)
		req = Net::HTTP::Lock.new("#{resource}")
		req['Depth'] = recursive ? 'infinite' : 0
		
		req.body = <<-EOF
		<?xml version="1.0" encoding="utf-8" ?>
		<D:lockinfo xmlns:D='DAV:'>
		<D:lockscope><D:exclusive/></D:lockscope>
		<D:locktype><D:write/></D:locktype>
		<D:owner>
		<D:href>http://www.icecrew.nl</D:href>
		</D:owner>
		</D:lockinfo>	
		EOF
		
		@http.request(req)
	end
	
	def unlock_resource(resource, token)
		req = Net::HTTP::Unlock.new("#{resource}")
		req['Lock-Token'] = token
		
		@http.request(req)
	end
	
	def assert_lock_xpath(doc, path)
		assert_not_nil(REXML::XPath.first(doc, "/multistatus/response/propstat/prop/lockdiscovery/activelock/#{path}", {'', 'DAV:'}))
	end
	
	def test_lock
		res = lock_resource('/file1')
		
		# Resulting code should be MultiStatus
		assert_code(WEBrick::HTTPStatus::MultiStatus, res)
		
		# Needs Lock-Token header
		assert_not_nil(res['Lock-Token'])
		
		# Check response content
		doc = REXML::Document.new(res.body)
		assert_lock_xpath(doc, 'lockscope/exclusive')
		assert_lock_xpath(doc, 'locktype/write')
		assert_lock_xpath(doc, 'locktoken/href')
		assert_lock_xpath(doc, 'depth[text() = "0"]')
		assert_lock_xpath(doc, 'owner/href[text() = "http://www.icecrew.nl"]')
		
		assert(res['Lock-Token'].gsub(/^<(.*)>$/, '\1'), REXML::XPath.first(doc, '/multistatus/response/propstat/prop/lockdiscovery/activelock/locktoken/href', {'', 'DAV:'}).text)
	end
	
	def test_unlock
		res = lock_resource('/file1')
		token = res['Lock-Token']
		
		res = unlock_resource('/file1', token)
		
		# Resulting code should be NoContent (204)
		assert_code(WEBrick::HTTPStatus::NoContent, res)
	end
	
	def test_locked_delete
		test_lock
		
		res = @http.request(Net::HTTP::Delete.new('/file1'))
		
		# Resulting code should be Locked (423)
		assert_code(WEBrick::HTTPStatus::Locked, res)
		
		# And file should still exist
		assert(exists?('file1'), 'File does not exist after delete failure!')
	end
	
	def test_locked_delete_owner
		res = lock_resource('/file1')
		
		req = Net::HTTP::Delete.new('/file1')
		req['If'] = "(#{res['Lock-Token']})"
		
		res = @http.request(req)
		
		# Resulting code should be NoContent
		assert_code(WEBrick::HTTPStatus::NoContent, res)
		
		# And file should be gone
		assert(!exists?('file1'), 'File should be deleted')
	end
	
	def test_lock_collection
		res = lock_resource('/folder1')
		assert_code(WEBrick::HTTPStatus::MultiStatus, res)		

		req = Net::HTTP::Delete.new('/folder1/file3')
		res = @http.request(req)
		
		# Resulting code should be Locked (423)
		assert_code(WEBrick::HTTPStatus::Locked, res)
		
		req = Net::HTTP::Delete.new('/folder1/folder2/file4')
		res = @http.request(req)
		
		# Resulting code should be NoContent
		assert_code(WEBrick::HTTPStatus::NoContent, res)
	end
	
	def test_lock_collection_infinite
		res = lock_resource('/folder1', true)
		
		req = Net::HTTP::Delete.new('/folder1/folder2/file4')
		res = @http.request(req)
		
		# Resulting code should be Locked (423)
		assert_code(WEBrick::HTTPStatus::Locked, res)
	end
	
	def test_lock_copy
		res = lock_resource('/')
		
		req = Net::HTTP::Copy.new('/file1')
		req['Destination'] = 'http://localhost:1111/filecopy'
		
		res = @http.request(req)
		
		# Resulting code should be Locked
		assert_code(WEBrick::HTTPStatus::Locked, res)
	end
	
	def test_lock_copy_locked_source
		res = lock_resource('/file1')
		
		req = Net::HTTP::Copy.new('/file1')
		req['Destination'] = 'http://localhost:1111/filecopy'
		
		res = @http.request(req)
		
		# Resulting code should be Created
		assert_code(WEBrick::HTTPStatus::Created, res)
	end
	
	def test_lock_move
		res = lock_resource('/')
		
		req = Net::HTTP::Move.new('/file1')
		req['Destination'] = 'http://localhost:1111/filerename'
		
		res = @http.request(req)
		
		# Resulting code should be Locked
		assert_code(WEBrick::HTTPStatus::Locked, res)
	end
	
	def test_lock_move_dest
		res = lock_resource('/folder1')
		
		req = Net::HTTP::Move.new('/file1')
		req['Destination'] = 'http://localhost:1111/folder1/filerename'
		
		res = @http.request(req)
		
		# Resulting code should be Locked
		assert_code(WEBrick::HTTPStatus::Locked, res)
	end
	
	def test_lock_mkcol
		res = lock_resource('/')
		
		req = Net::HTTP::Mkcol.new('/folder3')
		res = @http.request(req)
		
		# Resulting code should be Locked
		assert_code(WEBrick::HTTPStatus::Locked, res)
		assert(!exists?('folder3'), 'folder3 must not exist!')
	end
end


if $0 == __FILE__
	LockTest.run
end
