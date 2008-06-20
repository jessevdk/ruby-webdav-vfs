require 'vfs/properties'

module SqlFs
	class Properties < VFS::Properties
		def initialize(vfs, filename)
			super
		
			@stat = @vfs.find(filename)
			raise WEBrick::HTTPStatus::NotFound unless @stat
		end
		
		def creationdate
			@stat.ctime
		end
		
		def lastmodified
			@stat.mtime
		end
		
		def etag
			@stat.id
		end
		
		def contenttype
			@stat.directory ? "httpd/unix-directory" : WEBrick::HTTPUtils::mime_type(@filename, @vfs.config[:MimeTypes])
		end
		
		def contentlength
			raise WEBrick::HTTPStatus::NotFound if @stat.directory
			@stat.size.to_i or 0
		end
	end
end
