require 'rubygems'
require 'uuidtools'

module MemoryLocking
	module ClassMethods; end
	
	def MemoryLocking.included(other)
		other.extend(ClassMethods)
	end
	
	class Lock
		attr_reader :resource, :properties, :token
		
		def initialize(resource, properties)
			@resource = resource
			@properties = properties
			
			@token = UUID.random_create.to_s
		end
		
		def [](key)
			@properties[key]
		end
		
		def method_missing(meth, *args)
			@properties.include?(meth.to_sym) ? @properties[meth.to_sym] : nil
		end
		
		# Overload type, because ruby already defines it
		def type
			@properties[:type]
		end
		
		# Overload private timeout, who defines it, we don't know
		def timeout
			@properties[:timeout]
		end
	end
	
	module ClassMethods
		def locking?
			true
		end

		def lockstore
			@lockstore ||= Hash.new
		end
		
		def timeout=(timeout)
			@timeout = timeout
		end
		
		def locked?(resource, uid = nil)
			resource = "/#{resource}" unless resource[0] == ?/
			
			# Check if resource is directly locked
			return lockstore[resource] if lockstore.include?(resource)
			
			item = resource
			depth = 0
			
			# Check if resource is indirectly locked
			while true
				item = File.split(item).first
				
				if lockstore.include?(item)
					locks = check_timeout(item)
					
					locks.each do |lock|
						return lock if (lock.depth == 'infinite' or lock.depth == depth)
					end
				end

				break if item == '/'
				depth += 1
			end
			
			return nil
		end
		
		def check_timeout(resource)
			lockstore[resource].delete_if do |lock|
				lock.timeout and lock.timeout.downcase != 'infinite' and lock.timeout < Time.now
			end
			
			if lockstore[resource].empty?
				lockstore.delete(resource)
				[]
			else
				lockstore[resource]
			end
		end
		
		def child_locked?(resource, exclusive)
			# This method checks if some child in resource is locked
			lockstore.each do |key, value|
				next unless key.index(resource) == 0

				return true if exclusive
				
				value.each do |lock|
					return true if lock.scope == 'exclusive'
				end
			end
			
			false
		end
		
		def lock(resource, properties)
			# Check for direct locks of #resource
			locks = locked?(resource)
			
			if locks
				locks.each do |lock|
					return nil if (lock.scope == 'exclusive' || properties[:scope] == 'exclusive')
				end
			end
			
			# Check if something within #resource is already locked
			return nil if child_locked?(resource, properties[:scope])
			
			if @timeout and not properties.include?(:timeout)
				properties[:timeout] = @timeout
			end
			
			lock = Lock.new(resource, properties)
			lockstore[resource] = [lock, lockstore[resource]].flatten.compact

			lock
		end
		
		def unlock_all(resource)
			lockstore.delete(resource)
		end
		
		def refresh(lock)
			return unless lock.timeout or lock.timeout.downcase == 'infinite' or not @timeout
			
			lock.timeout += @timeout
		end
		
		def unlock(resource, token, uid = nil)
			locks = locked?(resource)
			match = nil

			if locks
				locks.each do |lock|
					if lock.token == token and lock.uid == uid
						match = lock
						break
					end
				end
			end
			
			return false unless match
			locks.delete(match)
			
			lockstore.delete(match.resource) if locks.empty?

			true
		end
	end
end
