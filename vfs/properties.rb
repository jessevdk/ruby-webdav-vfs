module VFS
	class Properties
		attr_reader :filename
		
		def initialize(vfs, filename)
			@filename = filename
			@vfs = vfs
		end
		
		def creationdate
		end
		
		def lastmodified
		end
		
		def etag
		end
		
		def contenttype
			@vfs.directory?(@filename) ? "httpd/unix-directory" : "text/plain"
		end
		
		def contentlength
			0
		end
	end
end
