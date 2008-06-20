#!/usr/bin/env ruby

require 'tests/testutilities'
require 'net/http'

class WebdavVfsTest < Test::Unit::TestCase
	include TestUtilities
	
	def test_mkcol
		req = Net::HTTP::Mkcol.new('/folder3')
		res = @http.request(req)
		
		# Resulting code should be Created
		assert_code(WEBrick::HTTPStatus::Created, res)
		assert(exists?('folder3'), 'folder3 was not created!')
	end
	
	def test_put
		req = Net::HTTP::Put.new('/filenew')
		res = @http.request(req)
		
		# Resulting code should be Created
		assert_code(WEBrick::HTTPStatus::OK, res)
		assert(exists?('filenew'), 'filenew was not created!')
	end
end

if $0 == __FILE__
	WebdavVfsTest.run
end
