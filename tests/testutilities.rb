require 'test/unit'
require 'test/unit/ui/console/testrunner'

require 'fileutils'
require 'webdavhandler'

module TestUtilities
	module ClassMethods; end

	def TestUtilities.included(other)
		other.extend(ClassMethods)
		
		logfile = "#{other.to_s.downcase}.log"
		File.unlink(logfile) if File.exist?(logfile)
	end
	
	module ClassMethods
		def run
			runner = Test::Unit::UI::Console::TestRunner

			if ARGV.empty? or ARGV.last == '0'
				runner.run(self)
			else
				suite = Test::Unit::TestSuite.new(self.to_s)

				ARGV.each {|x| suite << self.new(x)}
				runner.run(suite)
			end
		end
	end
	
	def setup_testfs
		d = File.dirname(File.expand_path(__FILE__))
		tfs = File.join(d, 'testfs')
	
		FileUtils.rm_rf(tfs) if File.exist?(tfs)
		FileUtils.mkdir(tfs)
		FileUtils.touch([File.join(tfs, 'file1')])
		FileUtils.touch([File.join(tfs, 'file2')])
	
		FileUtils.mkdir(File.join(tfs, 'folder1'))
		FileUtils.touch([File.join(tfs, 'folder1', 'file3')])
		
		FileUtils.mkdir(File.join(tfs, 'folder1', 'folder2'))
		FileUtils.touch([File.join(tfs, 'folder1', 'folder2', 'file4')])
	end

	def teardown_testfs
		d = File.dirname(File.expand_path(__FILE__))
		FileUtils.rm_rf([File.join(d, 'testfs')])
	end
	
	def setup
		setup_testfs
		
		Object.class_eval do
			remove_const 'LockedLocal' if const_defined?('LockedLocal')
		end
		
		load('tests/lockedlocal.rb')
		
		log = WEBrick::Log.new("#{self.class.to_s.downcase}.log")

		@server = WEBrick::HTTPServer.new({ 
			:Port => 1111, 
			:Logger => log, 
			:BindAddress => 'localhost',
			:AccessLog => [[log, WEBrick::AccessLog::COMMON_LOG_FORMAT]]
		})
		
		@serverthread = Thread.new do
			@server.mount("/", WEBrick::HTTPServlet::WebDAVHandler, 
				:Root => File.join(File.dirname(File.expand_path(__FILE__)), 'testfs'), 
				:VFS => LockedLocal)

			trap(:INT) { @server.shutdown }
			@server.start
		end

		@http = Net::HTTP.new('localhost', 1111)
	end
	
	def teardown
		@server.shutdown
		@serverthread.join
		
		teardown_testfs
	end
	
	def assert_code(webcode, res)
		assert_equal(webcode.code.to_i, res.code.to_i)
	end

	def exists?(filename)
		File.exists?("#{File.join(File.dirname(File.expand_path(__FILE__)))}/testfs/#{filename}")
	end
end
