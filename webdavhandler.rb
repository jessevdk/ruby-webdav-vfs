#
# webdavhandler.rb - WEBrick WebDAV handler
#
#	Author: Tatsuki Sugiura <sugi@nemui.org>
#	License: Ruby's
#

require 'time'
require 'fileutils.rb'
require 'rexml/document'
require 'webrick'
require 'webrick/httpservlet/filehandler'
require 'iconv'

module WEBrick
	class HTTPRequest
		# buffer is too small to transport huge files...
		if BUFSIZE < 512 * 1024
			remove_const :BUFSIZE
			BUFSIZE = 512 * 1024
		end
	end

	module Config
		webdavconf = {
			:FileSystemCoding			=> "UTF-8",
			:DefaultClientCoding		=> "UTF-8",
			:DefaultClientCodingWin		=> "CP932",
			:DefaultClientCodingMacx 	=> "UTF-8",
			:DefaultClientCodingUnix 	=> "EUC-JP",
			:NotInListName				=> %w(.*),
			:NondisclosureName			=> %w(.ht*),
		}
		WebDAVHandler = FileHandler.merge(webdavconf)
		WebDAVHandler[:MimeTypes] = HTTP[:MimeTypes].merge({"rb" => "application/x-ruby"})
	end

	module HTTPStatus
		new_StatusMessage = {
			102, 'Processing',
			207, 'Multi-Status',
			422, 'Unprocessable Entity',
			423, 'Locked',
			424, 'Failed Dependency',
			507, 'Insufficient Storage',
		}
		StatusMessage.each_key {|k| new_StatusMessage.delete(k)}
		StatusMessage.update new_StatusMessage

		new_StatusMessage.each{|code, message|
			var_name = message.gsub(/[ \-]/,'_').upcase
			err_name = message.gsub(/[ \-]/,'')
			
			case code
			when 100...200; parent = Info
			when 200...300; parent = Success
			when 300...400; parent = Redirect
			when 400...500; parent = ClientError
			when 500...600; parent = ServerError
			end

			eval %-
				RC_#{var_name} = #{code}
				class #{err_name} < #{parent}
					def self.code() RC_#{var_name} end
					def self.reason_phrase() StatusMessage[code] end
					def code() self::class::code end
					def reason_phrase() self::class::reason_phrase end
					alias to_i code
				end
			-

			CodeToError[code] = const_get(err_name)
		}
	end # HTTPStatus
end # WEBrick

module WEBrick; module HTTPServlet;
class WebDAVHandler < AbstractServlet
	class Unsupported < NotImplementedError; end
	class IgnoreProp < StandardError; end

	class CodeConvFilter
		module Detector
			def dav_ua(req)
				case req["USER-AGENT"]
				when /Microsoft Data Access Internet Publishing/
					{@options[:DefaultClientCodingWin] => 70, "UTF-8" => 30}
				when /^gnome-vfs/
					{"UTF-8" => 90}
				when /^WebDAVFS/
					{@options[:DefaultClientCodingMacx] => 80}
				when /Konqueror/
					{@options[:DefaultClientCodingUnix] => 60, "UTF-8" => 40}
				else
					{}
				end
			end

			def chk_utf8(req)
				begin 
					Iconv.iconv("UTF-8", "UTF-8", req.path, req.path_info)
					{"UTF-8" => 40}
				rescue Iconv::IllegalSequence
					{"UTF-8" => -500}
				end
			end

			def chk_os(req)
				case req["USER-AGENT"]
				when /Microsoft|Windows/i
					{@options[:DefaultClientCodingWin] => 10}
				when /UNIX|X11/i
					{@options[:DefaultClientCodingUnix] => 10}
				when /darwin|MacOSX/
					{"UTF-8" => 20}
				else 
					{}
				end
			end

			def default(req)
				{@options[:DefaultClientCoding] => 20}
			end
		end # Detector
	
		def initialize(options={}, default=Config::WebDAVHandler)
			@options = default.merge(options)
			@detect_meth = [:default, :chk_utf8, :dav_ua, :chk_os]
			@enc_score	 = Hash.new(0)
		end
		attr_accessor :detect_meth

		def detect(req)
			self.extend Detector
			detect_meth.each { |meth|
				score = self.__send__ meth, req
				@enc_score.update(score) {|enc, cur, new| cur + new}
			}
			#$DEBUG and $stderr.puts "code detection score ===> #{@enc_score.inspect}"
			platform_codename(@enc_score.keys.sort_by{|k| @enc_score[k] }.last)
		end

		def conv(req, from=nil, to="UTF-8")
			from ||= detect(req)
			#$DEBUG and $stderr.puts "=== CONVERT === #{from} -> #{to}"
			return true if from == to
			req.path_info = Iconv.iconv(to, from, req.path_info).first
			req.instance_variable_set :@path, Iconv.iconv(to, from, req.path).first
			req["destination"].nil? or req.instance_eval {
				@header["destination"][0] = HTTPUtils.escape(
					Iconv.iconv(to, from,
						HTTPUtils.unescape(@header["destination"][0])).first)
			}
			true
		end

		def conv2fscode!(req)
			conv(req, nil, @options[:FileSystemCoding])
		end

		def platform_codename(name)
			case RUBY_PLATFORM
			when /linux/
				name
			when /solaris|sunos/
				{
					"CP932"	=> "MS932",
					"EUC-JP" => "eucJP"
				}[name]
			when /aix/
				{
					"CP932"	=> "IBM-932",
					"EUC-JP" => "IBM-eucJP"
				}[name]
			else
				name
			end
		end
	end # CodeConvFilter

	def initialize(server, options={}, default=Config::WebDAVHandler)
		@config = server.config
		@root = options[:Root]
		@logger = @config[:Logger]
				
		@options = default.dup.update(options)
		@cconv = CodeConvFilter.new(@options)

		@vfs = @options[:VFS]
		@vfs.config = @config.merge(@options)
	end
	
	def service(req, res)
		codeconv_req!(req)
		
		if @vfs.respond_to?(:service)
			@vfs.service(req, res) do
				super
			end
		else
			super
		end
	end
	
	def do_GET(req, res)
		map_filename(req, res)
		properties = @vfs.properties(res.filename)

		res['etag'] = properties.etag
		mtime = properties.lastmodified

		if not_modified?(req, res, mtime, res['etag'])
			res.body = ''
			raise WEBrick::HTTPStatus::NotModified
		elsif req['range'] 
			make_partial_content(req, res, properties)
			raise WEBrick::HTTPStatus::PartialContent
		else
			res['content-type'] = properties.contenttype
			res['content-length'] = properties.contentlength
			res['last-modified'] = mtime.httpdate
			@vfs.stream(res.filename, "rb") do |f|
				res.body = f.read
			end
		end
	end
	
	def do_PUT(req, res)
		filename = File.join(@root, req.path_info)
		
		check_lock(req, res, filename)

		if req['range']
			ranges = HTTPUtils::parse_range_header(req['range']) or
				raise HTTPStatus::BadRequest,
					"Unrecognized range-spec: \"#{req['range']}\""
		end

		if !ranges.nil? && ranges.length != 1
			raise HTTPStatus::NotImplemented
		end

		begin						
			@vfs.iostream(filename) do |f|
				if ranges
					# TODO: supports multiple range
					#ranges.each do |range|
					#	first, last = prepare_range(range, filesize)
					#	first + req.content_length != last and
					#		raise HTTPStatus::BadRequest
					#	f.pos = first
					#	req.body {|buf| f << buf }
					#end
				else
					begin
						req.body do |buf|
							f << buf
						end
					rescue WEBrick::HTTPStatus::LengthRequired
					end
				end
			end
		rescue Errno::ENOENT
			raise HTTPStatus::Conflict
		rescue Errno::ENOSPC
			raise HTTPStatus::InsufficientStorage
		end
	end

	def do_LOCK(req, res)
		raise HTTPStatus::NotImplemented unless @vfs.locking?
		
		begin
			req_doc = REXML::Document.new req.body
		rescue REXML::ParseException
			raise HTTPStatus::BadRequest
		end
		
		resource = parse_filename(req, res)
		
		if req.body.nil?
			# Could be a lock refresh
			matches = parse_if_header(req, res)
			
			matches.each do |match|
				res = match[0].empty? ? resource : match[0]
				
				@vfs.locked?(res).each do |lock|
					@vfs.refresh(lock) if if_match(req, lock, [res, match[1]])
				end
			end
			
			raise HTTPStatus::NoContent
		else
			ns = {""=>"DAV:"}
			item = REXML::XPath.first(req_doc, "/lockinfo", ns)

			raise HTTPStatus::BadRequest unless item
			depth = req['Depth'] =~ /^infinite$/i ? 'infinite' : 0
			scope = (v = REXML::XPath.first(item, 'lockscope/*', ns)) && v.name
			type = (v = REXML::XPath.first(item, 'locktype/*', ns)) && v.name
			owner = REXML::XPath.first(item, 'owner/*', ns)
				
			# Try to lock the resource
			lock = @vfs.lock(resource, :depth => depth, :scope => scope, :type => type, :owner => owner, :uid => req.user)

			if not lock				
				res.body << build_multistat([[req.request_uri, elem_status(req, res, HTTPStatus::Locked)]]).to_s

				res["Content-Type"] = 'text/xml; charset="utf-8"'
				raise HTTPStatus::MultiStatus
			end
			
			# Respond with propfinding the lockdiscovery property
			res['Lock-Token'] = "<opaquelocktoken:#{lock.token}>"
			propfind_response(req, res, ['lockdiscovery'], 0)
		end
	end
	
	def do_UNLOCK(req, res)
		raise HTTPStatus::NotImplemented unless @vfs.locking?
		
		resource = parse_filename(req, res)
		
		if not req['Lock-Token'] =~ /<opaquelocktoken:(.*)>/
			raise HTTPStatus::BadRequest
		end
		
		if @vfs.unlock(resource, $1, req.user)
			raise HTTPStatus::NoContent
		else
			raise HTTPStatus::Forbidden
		end
	end

	def do_OPTIONS(req, res)
		@logger.debug "run do_OPTIONS"
		
		res["DAV"] = @vfs.locking? ? "2" : "1"
		res["MS-Author-Via"] = "DAV"
		super
	end

	def propfind_response(req, res, props, depth)
		filename = parse_filename(req, res)

		if not @vfs.exists?(filename)
			raise HTTPStatus::NotFound
		end

		ret = get_rec_prop(req, res, filename, HTTPUtils.escape(codeconv_str_fscode2utf(req.path)), props, *[depth].compact)

		res.body << build_multistat(ret).to_s
		res["Content-Type"] = 'text/xml; charset="utf-8"'
		raise HTTPStatus::MultiStatus
	end

	def do_PROPFIND(req, res)
		map_filename(req, res)
		
		@logger.debug "propfind requeset depth=#{req['Depth']}"
		depth = (req["Depth"].nil? || req["Depth"] == "infinity") ? nil : req["Depth"].to_i
		raise HTTPStatus::Forbidden unless depth # deny inifinite propfind

		begin
			req_doc = REXML::Document.new req.body
		rescue REXML::ParseException
			raise HTTPStatus::BadRequest
		end

		ns = {""=>"DAV:"}
		req_props = []
		all_props = %w(creationdate getlastmodified getetag resourcetype getcontenttype getcontentlength displayname)
		
		if @vfs.locking?
			all_props += %w(supportedlock lockdiscovery)
		end	 

		if req.body.nil? || !REXML::XPath.match(req_doc, "/propfind/allprop", ns).empty?
			req_props = all_props
		elsif !REXML::XPath.match(req_doc, "/propfind/propname", ns).empty?
			# TODO: support propname
			raise HTTPStatus::NotImplemented
		elsif !REXML::XPath.match(req_doc, "/propfind/prop", ns).empty?
			REXML::XPath.each(req_doc, "/propfind/prop/*", ns){|e|
				req_props << e.name
			}
		else
			raise HTTPStatus::BadRequest
		end

		propfind_response(req, res, req_props, depth)		
	end

	def do_PROPPATCH(req, res)
		map_filename(req, res)
		
		if not @vfs.exist?(res.filename)
			raise HTTPStatus::NotFound
		end
		
		ret = []
		ns = {""=>"DAV:"}
		begin
			req_doc = REXML::Document.new req.body
		rescue REXML::ParseException
			raise HTTPStatus::BadRequest
		end
		REXML::XPath.each(req_doc, "/propertyupdate/remove/prop/*", ns){|e|
			ps = REXML::Element.new "D:propstat"
			ps.add_element("D:prop").add_element "D:" + e.name
			ps << elem_status(req, res, HTTPStatus::Forbidden)
			ret << ps
		}
		REXML::XPath.each(req_doc, "/propertyupdate/set/prop/*", ns){|e|
			ps = REXML::Element.new "D:propstat"
			ps.add_element("D:prop").add_element "D:" + e.name
			begin
				e.namespace.nil? || e.namespace == "DAV:" or raise Unsupported
				case e.name
				when "getlastmodified"
					@vfs.set_lastmodified(Time.httpdate(e.text), res.filename)
				else
					raise Unsupported
				end
				ps << elem_status(req, res, HTTPStatus::OK)
			rescue Errno::EACCES, ArgumentError
				ps << elem_status(req, res, HTTPStatus::Conflict)
			rescue Unsupported
				ps << elem_status(req, res, HTTPStatus::Forbidden)
			rescue
				ps << elem_status(req, res, HTTPStatus::InternalServerError)
			end
			ret << ps
		}
		res.body << build_multistat([[req.request_uri, *ret]]).to_s
		res["Content-Type"] = 'text/xml; charset="utf-8"'
		raise HTTPStatus::MultiStatus
	end

	def do_MKCOL(req, res)
		req.body.nil? or raise HTTPStatus::MethodNotAllowed

		filename = File.join(@root, req.path_info)
		check_lock(req, res, filename)

		begin
			@vfs.mkdir(filename)
		rescue Errno::ENOENT, Errno::EACCES
			raise HTTPStatus::Forbidden
		rescue Errno::ENOSPC
			raise HTTPStatus::InsufficientStorage
		rescue Errno::EEXIST
			raise HTTPStatus::Conflict
		end
		raise HTTPStatus::Created
	end
	
	def parse_if_header(req, res)
		return [] unless req['If']
		
		matches = []
		token = '<[^>]*>'
		req['If'].scan(/(#{token})?(\s*\(((#{token})|\[([^\]]*)\]\s*)+\))+/) do |resource, lst, token|
			if resource
				resource = File.join(@root, normalize_path(req, resource.gsub(/(<|>)/, '')))
			else
				resource = parse_filename(req, res)
			end
		
			matches << [resource, token.gsub(/(<|>)/, '').gsub(/^opaquelocktoken:/, '')]
		end

		matches
	end
	
	def if_match(req, lock, match)
		
		return false unless lock.token == match[1]
		return false unless lock.uid == req.user
		return false if not match[0].empty? and lock.resource != match[0]

		true
	end
	
	def check_lock(req, res, resource = nil)
		return nil unless @vfs.locking?
		
		# Get locks on this resource
		locks = @vfs.locked?(resource || res.filename)
		return nil unless locks

		# Check if the current user is the owner of one of the locks
		matches = parse_if_header(req, res)
		
		locks.each do |lock|
			matches.each do |match|
				return lock if if_match(req, lock, match)
			end
		end
		
		raise HTTPStatus::Locked
	end

	def do_DELETE(req, res)
		map_filename(req, res)
		lock = check_lock(req, res)

		begin
			@vfs.remove(res.filename)
			
			@vfs.unlock_all(lock.resource) if @vfs.locking? and lock
		rescue Errno::EPERM
			raise HTTPStatus::Forbidden
		end
		raise HTTPStatus::NoContent
	end

	def do_COPY(req, res)
		src, dest, depth, exists_p = cp_mv_precheck(req, res)
		@logger.debug "copy #{src} -> #{dest}"
		begin
			if depth.nil? # infinity
				@vfs.copy(src, dest, true)
			elsif depth == 0
				@vfs.copy(src, dest, false)
			end
		rescue Errno::ENOENT
			raise HTTPStatus::Conflict
			# FIXME: use multi status(?) and check error URL.
		rescue Errno::ENOSPC
			raise HTTPStatus::InsufficientStorage
		end

		raise exists_p ? HTTPStatus::NoContent : HTTPStatus::Created
	end

	def do_MOVE(req, res)
		src, dest, depth, exists_p = cp_mv_precheck(req, res)
		
		begin
			@vfs.move(src, dest)
			
			lock = check_lock(req, res, src)
			@vfs.unlock_all(lock.resource) if @vfs.locking? and lock
		rescue Errno::ENOENT
			raise HTTPStatus::Conflict
			# FIXME: use multi status(?) and check error URL.
		rescue Errno::ENOSPC
			raise HTTPStatus::InsufficientStorage
		end

		if exists_p
			raise HTTPStatus::NoContent
		else
			raise HTTPStatus::Created
		end
	end


	######################
	private 
			
	def cp_mv_precheck(req, res)
		depth = (req["Depth"].nil? || req["Depth"] == "infinity") ? nil : req["Depth"].to_i
		depth.nil? || depth == 0 or raise HTTPStatus::BadRequest
		@logger.debug "copy/move requested. Deistnation=#{req['Destination']}"
		dest_uri = URI.parse(req["Destination"])
		unless "#{req.host}:#{req.port}" == "#{dest_uri.host}:#{dest_uri.port}"
			raise HTTPStatus::BadGateway
			# TODO: anyone needs to copy other server?
		end
		src	= parse_filename(req, res)
		dest = File.join(@root, resolv_destpath(req))

		src == dest and raise HTTPStatus::Forbidden
		
		if req.request_method == 'MOVE'
			# MOVE - check lock on source
			check_lock(req, res, src)
		end

		check_lock(req, res, dest)

		exists_p = false
		if @vfs.exists?(dest)
			exists_p = true
			if req["Overwrite"] == "T"
				@logger.debug "copy/move precheck: Overwrite flug=T, deleteing #{dest}"
				@vfs.remove(dest)
			else
				raise HTTPStatus::PreconditionFailed
			end
		end
		
		return *[src, dest, depth, exists_p]
	end

	def codeconv_req!(req)
		@logger.debug "codeconv req obj: orig; path_info='#{req.path_info}', dest='#{req["Destination"]}'"
		begin
			@cconv.conv2fscode!(req)
		rescue Iconv::IllegalSequence
			@logger.warn "code conversion fail! for request object. #{@cconv.detect(req)}->(fscode)"
		end
		@logger.debug "codeconv req obj: ret; path_info='#{req.path_info}', dest='#{req["Destination"]}'"
		true
	end

	def codeconv_str_fscode2utf(str)
		return str if @options[:FileSystemCoding] == "UTF-8"
		@logger.debug "codeconv str fscode2utf: orig='#{str}'"
		begin
			ret = Iconv.iconv("UTF-8", @options[:FileSystemCoding], str).first
		rescue Iconv::IllegalSequence
			@logger.warn "code conversion fail! #{@options[:FileSystemCoding]}->UTF-8 str=#{str.dump}"
			ret = str
		end
		@logger.debug "codeconv str fscode2utf: ret='#{ret}'"
		ret
	end

	def parse_filename(req, res)
		if @vfs.respond_to?(:parse_filename)
			filename = @vfs.parse_filename(req, res)
		else
			filename = ((req.path_info and File.join(@root, req.path_info)) or @root)
			filename.gsub(/\/+$/, '')
		end

		filename
	end

	def map_filename(req, res)
		raise HTTPStatus::NotFound, "`#{req.path}' not found" unless @root
		res.filename = parse_filename(req, res)
	end

	def build_multistat(rs)
		m = elem_multistat
		rs.each {|href, *cont|
			res = m.add_element "D:response"
			res.add_element("D:href").text = href
			cont.flatten.each {|c| res.elements << c}
		}
		REXML::Document.new << m
	end

	def elem_status(req, res, retcodesym)
		gen_element("D:status", "HTTP/#{req.http_version} #{retcodesym.code} #{retcodesym.reason_phrase}")
	end

	def get_rec_prop(req, res, file, r_uri, props, depth = 5000)
		ret_set = []
		depth -= 1
		ret_set << [r_uri, get_propstat(req, res, file, props)]
		
		@logger.debug "get prop file='#{file}' depth=#{depth}"
		return ret_set if !(@vfs.directory?(file) && depth >= 0)

		@vfs.entries(file) {|d|
			if @vfs.directory?("#{file}/#{d}")
				ret_set += get_rec_prop(req, res, "#{file}/#{d}",
																HTTPUtils.normalize_path(
																	r_uri+HTTPUtils.escape(
																		codeconv_str_fscode2utf("/#{d}/"))),
																props, depth)
			else 
				ret_set << [HTTPUtils.normalize_path(
											r_uri+HTTPUtils.escape(
												codeconv_str_fscode2utf("/#{d}"))),
					get_propstat(req, res, "#{file}/#{d}", props)]
			end
		}
		ret_set
	end
	
	def elem_error_status(req, res, name, err)
		r = REXML::Element.new
	end

	def get_propstat(req, res, file, props)
		propstats = []
		propstat = REXML::Element.new "D:propstat"
		propstats << propstat
		
		errstat = {}
		begin
			st = @vfs.properties(file)
			pe = REXML::Element.new "D:prop"
			props.each {|pname|
				begin 
					if respond_to?("get_prop_#{pname}", true)
						pe << __send__("get_prop_#{pname}", req, st)
					else
						raise HTTPStatus::NotFound
					end
				rescue IgnoreProp
					# simple ignore
				rescue HTTPStatus::Status => e
					# FIXME: add to errstat
					ps = REXML::Element.new("D:propstat")
					ps << gen_element('D:prop', gen_element("D:#{pname}"))
					ps << elem_status(req, res, e)
					
					propstats << ps
				end
			}
			propstat.elements << pe
			propstat.elements << elem_status(req, res, HTTPStatus::OK)
		rescue Exception => e
			propstat.elements << elem_status(req, res, HTTPStatus::InternalServerError)
		end

		propstats
	end
	
	def get_prop_displayname(req, props)
		gen_element "D:displayname", props.displayname
	end

	def get_prop_creationdate(req, props)
		gen_element "D:creationdate", props.creationdate.xmlschema
	end

	def get_prop_getlastmodified(req, props)
		if req['user-agent'] and req['user-agent'] =~ /gvfs/
			d = props.lastmodified.xmlschema
		else
			d = props.lastmodified.httpdate
		end
		
		gen_element "D:getlastmodified", d
	end

	def get_prop_getetag(req, props)
		gen_element "D:getetag", props.etag
	end

	def get_prop_resourcetype(req, props)
		t = gen_element "D:resourcetype"
		@vfs.directory?(props.filename) and t.add_element("D:collection")
		t
	end

	def get_prop_getcontenttype(req, props)
		gen_element("D:getcontenttype", props.contenttype)
	end

	def get_prop_getcontentlength(req, props)
		gen_element "D:getcontentlength", props.contentlength
	end
	
	def get_prop_lockdiscovery(req, props)
		raise HTTPStatus::NotFound unless @vfs.locking?
		
		locks = @vfs.locked?(props.filename)
		raise IgnoreProp unless locks
		
		discovery = REXML::Element.new('D:lockdiscovery')
		
		locks.each do |lock|
			e = lock_entry('activelock', lock.scope, lock.type)
			e << gen_element('D:depth', lock.depth)
		
			if lock.owner
				owner = REXML::Element.new('D:owner')
				owner << lock.owner
				
				e << owner
			end
		
			if lock.timeout
				e << gen_element('D:timeout', lock.timeout)
			end
		
			token = REXML::Element.new('D:locktoken') 
			token << gen_element('D:href', "opaquelocktoken:#{lock.token}")
			
			e << token
			
			discovery << e
		end
		
		discovery
	end
	
	def lock_entry(name, scope, type)
		entry = REXML::Element.new("D:#{name}")
		
		entry << gen_element('D:lockscope', scope ? gen_element("D:#{scope}") : nil)
		entry << gen_element('D:locktype', type ? gen_element("D:#{type}") : nil)
		
		entry
	end
	
	def get_prop_supportedlock(req, props)
		e = REXML::Element.new('D:supportedlock')
		e << lock_entry('lockentry', 'exclusive', 'write')
		e << lock_entry('lockentry', 'shared', 'write')
		
		e
	end

	def elem_multistat
		gen_element "D:multistatus", nil, {"xmlns:D" => "DAV:"}
	end

	def gen_element(elem, child = nil, attrib = {})
		e = REXML::Element.new(elem)
		
		if child.is_a?(REXML::Element)
			e << child
		elsif child
			e.text = child.to_s
		end
		
		attrib.each {|k, v| e.attributes[k] = v }
		e
	end

	def normalize_path(req, path)
	 	unescape = HTTPUtils.unescape(URI.parse(path).path)

		if /^#{Regexp.escape(req.script_name)}/ =~ unescape
			return $'
		else
			return unescape
		end
	end

	def resolv_destpath(req)
		normalize_path(req, req['Destination'])
	end
	
	def not_modified?(req, res, mtime, etag)
		if ir = req['if-range']
			begin
				if Time.httpdate(ir) >= mtime
					return true
				end
			rescue
				if HTTPUtils::split_header_value(ir).member?(res['etag'])
					return true
				end
			end
		end

		if (ims = req['if-modified-since']) && Time.parse(ims) >= mtime
			return true
		end

		if (inm = req['if-none-match']) &&
			 HTTPUtils::split_header_value(inm).member?(res['etag'])
			return true
		end

		return false
	end
	
	def prepare_range(range, filesize)
		first = range.first < 0 ? filesize + range.first : range.first
		
		return -1, -1 if first < 0 || first >= filesize
		
		last = range.last < 0 ? filesize + range.last : range.last
		last = filesize - 1 if last >= filesize
		
		return first, last
	end
	
	def make_partial_content(req, res, properties)
		mtype = properties.contenttype
		filesize = properties.contentlength
	
		unless ranges = WEBrick::HTTPUtils::parse_range_header(req['range'])
			raise WEBrick::HTTPStatus::BadRequest,
				"Unrecognized range-spec: \"#{req['range']}\""
		end
	
		@vfs.stream(properties.filename, "rb") do |io|
			if ranges.size > 1
				time = Time.now
				boundary = "#{time.sec}_#{time.usec}_#{Process::pid}"
				body = ''
			
				ranges.each do |range|
					first, last = prepare_range(range, filesize)
					next if first < 0
				
					io.pos = first
					content = io.read(last - first + 1)

					body << "--" << boundary << CRLF
					body << "Content-Type: #{mtype}" << CRLF
					body << "Content-Range: #{first}-#{last}/#{filesize}" << CRLF
					body << CRLF
					body << content
					body << CRLF
				end
			
				raise WEBrick::HTTPStatus::RequestRangeNotSatisfiable if body.empty?
				body << "--" << boundary << "--" << CRLF
				res["content-type"] = "multipart/byteranges; boundary=#{boundary}"
				res.body = body
			elsif range = ranges[0]
				if filesize == 0 and range.first == 0 and range.last == -1 then
					first, last = 0, 0
				else
					first, last = prepare_range(range, filesize)				
				end

				raise WEBrick::HTTPStatus::RequestRangeNotSatisfiable if first < 0
			
				if filesize != 0
					if last == properties.contentlength - 1
						d = io.dup
						d.pos = first
						
						content = d.read
					else
						io.pos = first
						content = io.read(last - first + 1)
					end
				end
				
				res['content-type'] = mtype
				res['content-range'] = "#{first}-#{last}/#{filesize}"
				res['content-length'] = filesize == 0 ? 0 : last - first + 1
				res.body = content
			else
				raise WEBrick::HTTPStatus::BadRequest
			end
		end
	end
end # WebDAVHandler
end; end # HTTPServlet; WEBrick
