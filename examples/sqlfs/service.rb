require 'vfs/abstract'
require 'properties'
require 'entry'
require 'vfs/stringstream'
require 'webrick'

module SqlFs
	class Service < VFS::Abstract
		def self.properties(filename)
			SqlFs::Properties.new(self, filename)
		end
		
		def self.split_filename(filename)
			if filename[0] != ?/
				filename = "/#{filename}"
			end
			
			parts = []
			
			while (filename, part = File.split(filename)) and filename != part
				parts.unshift(part) unless part == '/'
			end
			
			parts
		end
		
		def self.find(filename, err = nil)
			if filename.is_a?(String)
				filename = split_filename(filename)
			end
			
			Entry.find_path(filename) or (err and raise err)
		end
		
		def self.stream(filename, acc)
			case acc
			when /^[ra]\+?/
				f = find(filename, WEBrick::HTTPStatus::NotFound)
			when /^w\+?/
				# Truncate or create new file
				f = find(filename)
				
				if f
					f.content = ''
				else
					# Try to create new empty file
					parts = File.split(filename)
					d = find(parts.first, WEBrick::HTTPStatus::NotFound)
					
					raise WEBrick::HTTPStatus::NotFound unless d.directory
					f = d.entries.create(:name => parts.last, :mtime => Time.now, :ctime => Time.now, :directory => 0)
				end
			end
			
			if f.directory
				raise WEBrick::HTTPStatus::NotFound
			end

			s = VFS::StringStream.new(f.content, acc)
			yield s
			
			if acc =~ /w/
				# Save result
				f.content = s.buffer.empty? ? nil : s.buffer
				f.save!
			end
		end
		
		def self.set_lastmodified(filename, mtime)
			f = find(filename)
			f.mtime = mtime

			f.save!
		end
		
		def self.directory?(filename)
			(f = find(filename)) and f.directory
		end
		
		def self.mkdir(filename)
			parts = File.split(filename)
			f = find(parts.first, WEBrick::HTTPStatus::NotFound)
			
			f.entries.create(:name => parts.last, :mtime => Time.now, :ctime => Time.now, :directory => 1).save!
		end
		
		def self.remove(filename)
			find(filename, WEBrick::HTTPStatus::NotFound).destroy
		end
		
		def self.copy_recursive(source, destdir, name)
			if source.directory
				# Create the directory
				newparent = destdir.entries.create(:name => name, :mtime => Time.now, :ctime => Time.now, :directory => 1)
				newparent.save!
				
				# Get children
				source.entries.each do |child|
					copy_recursive(child, newparent, child.name)
				end
			else
				copy_entry(source, destdir, item)
			end
		end
		
		def self.copy_entry(entry, parent, name)
			parent.entries.create(:name => name, :mtime => Time.now, :ctime => Time.now, :directory => 0, :content => entry.content).save!
		end
		
		def self.copy(src, dst, recursive=true)
			 # Find source item
			 f = find(src, WEBrick::HTTPStatus::NotFound)
			 
			 # Find destination directory
			 parts = File.split(dst)
			 parent = find(parts.first, WEBrick::HTTPStatus::NotFound)
			 
			 if f.directory
			 	if recursive
			 		copy_recursive(f, parent, parts.last)
			 	else
			 		mkdir(dst)
			 	end
			 else
			 	# Simply copy
			 	copy_entry(f, parent, parts.last)
			 end
		end
		
		def self.move(src, dst)
			f = find(src, WEBrick::HTTPStatus::NotFound)
			
			parts = File.split(dst)
			d = find(parts.first, WEBrick::HTTPStatus::NotFound)
			
			f.parent = d.id
			f.name = parts.last
			f.save!
		end
		
		def self.exists?(filename)
			find(filename) != nil
		end
		
		def self.filtered?(filename)
			false
		end
		
		def self.entries(dirname)
			item = find(dirname)
			raise WEBrick::HTTPStatus::NotFound unless item
			
			item.entries.each do |child|
				yield child.name
			end
		end
		
		def self.service(req, res)
			ActiveRecord::Base.allow_concurrency = true
			yield
			ActiveRecord::Base.verify_active_connections!
		end
	end
end
