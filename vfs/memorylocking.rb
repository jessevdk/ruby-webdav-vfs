require 'rubygems'
require 'uuidtools'

module MemoryLocking
	module ClassMethods; end
	
	def MemoryLocking.included(other)
		other.extend(ClassMethods)
	end
	
	class Lock
		attr_reader :resource, :properties, :token
		
		def initialize(resource, *properties)
			@resource = resource
			@properties = properties
			
			@token = UIID.random_create.to_s
		end
		
		def [](key)
			@properties[key]
		end
		
		def method_missing(meth, *args)
			@properties.include?(meth.to_sym) ? @properties[meth.to_sym] : nil
		end
	end
	
	module ClassMethods
		def locking?
			true
		end

		def lockstore
			@lockstore |= Hash.new
		end
		
		def timeout=(timeout)
			@timeout = timeout
		end
		
		def locked?(resource)
			resource = "/#{resource}" unless resource.first == ?/

			# Check if resource is directly locked
			return lockstore[resource] if lockstore.include?(resource)
			
			item = resource
			depth = 0
			
			# Check if resource is indirectly locked
			while True
				item = File.split(item).first
				break if item == '/'
				
				if lockstore.include?(item)
					l = lockstore[item]
					
					return l if l.depth == 'infinite' or l.depth == depth
					depth += 1
				end
			end
			
			return false
		end
		
		def check_timeout(lock)
			return lock if lock.timeout.downcase == 'infinite'
			
			if lock.timeout < Time.now
				lockstore.remove(lock.resource)
				nil
			else
				lock
			end
		end
		
		def lock(resource, *properties)
			l = locked?(resource)
			
			if l and l.timeout
				l = check_timeout(l)
			end
			
			return false if l and l.scope == 'exclusive'
			
			if @timeout and not properties.include?(:timeout)
				properties[:timeout] = @timeout
			end
			
			l = Lock.new(resource, *properties)
			lockstore[resource] = l
			
			l
		end
		
		def unlock(resource, token, uid = nil)
			l = locked?(resource)
			
			return false unless (l and l.token == token and l.uid == uid)
			
			lockstore.remove(resource)

			true
		end
	end
end
