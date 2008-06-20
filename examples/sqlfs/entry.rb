require 'active_record'
require 'db'

module SqlFs
	# Virtual Filesystem Entry model. This model represents an entries table
	# with a simple hierarchical mapping
	class Entry < ActiveRecord::Base
		@@retry = false
				
		SqlFs::Database::connect
		
		has_many :entries, :foreign_key => :parent
		belongs_to :entry, :foreign_key => :parent
		
		def self.find(*args)
			# Make sure to very active connections
			ActiveRecord::Base.verify_active_connections!
		
			begin
				super
			rescue Exception => e
				# Try to reconnect if the find failed
				if not @@retry
					@@retry = true
					ActiveRecord::Base.connection.reconnect!
					retry
				else
					@@retry = false
				end
			end
		end
		
		# Find an entry specified by a path array
		def self.find_path(parts)
			return nil unless parts
			
			# Find the root
			item = find_by_parent(nil)
			return nil unless item
			
			parts = parts.dup
			
			# For each part, find the entry with the previous item as parent
			while not parts.empty? and item
				item = find(:first, :select => '*, LENGTH(content) AS size', :conditions => ['parent = ? AND name = ?', item.id, parts.shift])
			end
			
			item
		end
	end
end
