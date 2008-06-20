require 'active_record'

module SqlFs
	class Database
		MUTEX = Mutex.new
		
		def self.connect
			ActiveRecord::Base.establish_connection(
				:adapter  => "mysql",
				:host     => "localhost",
				:socket   => "/var/run/mysqld/mysqld.sock",
				:username => "sqlfs",
				:password => "sqlfs",
				:database => "sqlfs"
			)

			ActiveRecord::Base.verification_timeout = 7000
		end
	end
end
