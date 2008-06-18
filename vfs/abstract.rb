require 'vfs/properties'
require 'webrick'

module VFS	
	class Abstract
		def self.config=(config)
			@config = config
		end
		
		def self.config
			@config
		end
		
		def self.stream(filename, acc)
			raise WEBrick::HTTPStatus::NotImplemented
		end
		
		def self.iostream(filename)
			stream(filename, "w+") {|f| yield f}
		end
		
		def self.ostream(filename)
			stream(filename, "w") {|f| yield f}
		end
		
		def self.istream(filename)
			stream(filename, "r") {|f| yield f}
		end
		
		def self.set_lastmodified(filename, mtime)
			raise WEBrick::HTTPStatus::NotImplemented
		end
		
		def self.directory?(filename)
			raise WEBrick::HTTPStatus::NotImplemented
		end
		
		def self.mkdir(filename)
			raise WEBrick::HTTPStatus::NotImplemented
		end
		
		def self.remove(filename)
			raise WEBrick::HTTPStatus::NotImplemented
		end
		
		def self.copy(src, dst, recursive=true)
			raise WEBrick::HTTPStatus::NotImplemented
		end
		
		def self.move(src, dst)
			raise WEBrick::HTTPStatus::NotImplemented
		end
		
		def self.exists?(filename)
			raise WEBrick::HTTPStatus::NotImplemented
		end
		
		def self.filtered?(filename)
			false
		end
		
		def self.entries(dirname)
			raise WEBrick::HTTPStatus::NotImplemented
		end
		
		def self.properties(filename)
			Properties.new(self, filename)
		end
	end
end
