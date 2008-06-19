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
		
		def locked?(resource, uid = nil)
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
					locks = check_timeout(item)
					
					locks.each do |lock|
						return lock if lock.dept == 'infinite' or lock.depth == depth
					end

					depth += 1
				end
			end
			
			return false
		end
		
		def check_timeout(resource)
			lockstore[resource].delete_if! do |lock|
				lock.timeout and lock.timeout.downcase != 'infinite' and lock.timeout < Time.now
			end
			
			if lockstore[resource].empty?
				lockstore.remove(resource)
				[]
			else
				lockstore[resource]
			end
		end
		
		def lock(resource, *properties)
			locks = locked?(resource)
			
			if locks
				locks.each do |lock|
					return nil if lock.scope == 'exclusive'
				end
			end
			
			if @timeout and not properties.include?(:timeout)
				properties[:timeout] = @timeout
			end
			
			lock = Lock.new(resource, *properties)
			lockstore[resource] = [lock, lockstore[resource]].flatten.compact
			
			lock
		end
		
		def unlock_all(resource)
			lockstore.remove(resource)
		end
		
		def unlock(resource, token, uid = nil)
			locks = locked?(resource)
			match = nil

			if locks
				locks.each do |lock|
					match = lock.token == token and lock.uid == uid
					break if match
				end
			end
			
			return false unless match
			locks.remove(match)
			
			lockstore.remove(match.resource) if locks.emty?

			true
		end
	end
end
