require "zlib"

module Amber
  module Pipe
    class Static < HTTP::StaticFileHandler
      @directory_listing = false
      @fallthrough = false

      def call(context : HTTP::Server::Context)
        return call_next(context) if context.request.path.not_nil! == "/"

        unless context.request.method == "GET" || context.request.method == "HEAD"
          if @fallthrough
            call_next(context)
          else
            context.response.status_code = 405
            context.response.headers.add("Allow", "GET, HEAD")
          end
          return
        end

        config = static_config
        original_path = context.request.path.not_nil!
        is_dir_path = original_path.ends_with? "/"
        request_path = URI.unescape(original_path)

        # File path cannot contains '\0' (NUL) because all filesystem I know
        # don't accept '\0' character as file name.
        if request_path.includes? '\0'
          context.response.status_code = 400
          return
        end

        expanded_path = File.expand_path(request_path, "/")
        if is_dir_path && !expanded_path.ends_with? "/"
          expanded_path = "#{expanded_path}/"
        end
        is_dir_path = expanded_path.ends_with? "/"

        file_path = File.join(@public_dir, expanded_path)
        is_dir = Dir.exists? file_path

        if request_path != expanded_path || is_dir && !is_dir_path
          redirect_to context, "#{expanded_path}#{is_dir && !is_dir_path ? "/" : ""}"
        end

        if Dir.exists?(file_path)
          if config.is_a?(Hash) && config["dir_listing"] == true
            context.response.content_type = "text/html"
            directory_listing(context.response, request_path, file_path)
          else
            return call_next(context)
          end
        elsif File.exists?(file_path)
          return if etag(context, file_path)
          serve_file(context, file_path)
        else
          call_next(context)
        end
      end

      private def static_config
        {"dir_listing" => @directory_listing, "gzip" => true}
      end

      private def etag(context, file_path)
        etag = %{W/"#{File.lstat(file_path).mtime.epoch.to_s}"}
        context.response.headers["ETag"] = etag
        return false if !context.request.headers["If-None-Match"]? || context.request.headers["If-None-Match"] != etag
        context.response.headers.delete "Content-Type"
        context.response.content_length = 0
        context.response.status_code = 304 # not modified
        return true
      end

      private def mime_type(path)
        Support::MimeTypes.mime_type File.extname(path)
      end

      private def serve_file(env, path : String, mime_type : String? = nil)
        config = static_config
        file_path = File.expand_path(path, Dir.current)
        mime_type ||= mime_type(file_path)
        env.response.content_type = mime_type
        minsize = 860 # http://webmasters.stackexchange.com/questions/31750/what-is-recommended-minimum-object-size-for-gzip-performance-benefits ??
        request_headers = env.request.headers
        filesize = File.size(file_path)
        File.open(file_path) do |file|
          if env.request.method == "GET" && env.request.headers.has_key?("Range")
            next multipart(file, env)
          end
          if request_headers.includes_word?("Accept-Encoding", "gzip") && config.is_a?(Hash) && config["gzip"] == true && filesize > minsize && Support::MimeTypes.zip_types(file_path)
            env.response.headers["Content-Encoding"] = "gzip"
            Gzip::Writer.open(env.response) do |deflate|
              IO.copy(file, deflate)
            end
          elsif request_headers.includes_word?("Accept-Encoding", "deflate") && config.is_a?(Hash) && config["gzip"]? == true && filesize > minsize && Support::MimeTypes.zip_types(file_path)
            env.response.headers["Content-Encoding"] = "deflate"
            Flate::Writer.new(env.response) do |deflate|
              IO.copy(file, deflate)
            end
          else
            env.response.content_length = filesize
            IO.copy(file, env.response)
          end
        end
        return
      end

      private def multipart(file, env)
        # See http://httpwg.org/specs/rfc7233.html
        fileb = file.size

        range = env.request.headers["Range"]
        match = range.match(/bytes=(\d{1,})-(\d{0,})/)

        startb = 0
        endb = 0

        if match
          if match.size >= 2
            startb = match[1].to_i { 0 }
          end

          if match.size >= 3
            endb = match[2].to_i { 0 }
          end
        end

        if endb == 0
          endb = fileb - 1
        end

        if startb < endb && endb <= fileb
          env.response.status_code = 206
          env.response.content_length = (endb - startb) + 1
          env.response.headers["Accept-Ranges"] = "bytes"
          env.response.headers["Content-Range"] = "bytes #{startb}-#{endb}/#{fileb}" # MUST

          if startb > 1024
            skipped = 0
            # file.skip only accepts values less or equal to 1024 (buffer size, undocumented)
            until skipped + 1024 > startb
              file.skip(1024)
              skipped += 1024
            end
            if skipped - startb > 0
              file.skip(skipped - startb)
            end
          else
            file.skip(startb)
          end

          IO.copy(file, env.response, endb - startb)
        else
          env.response.content_length = fileb
          env.response.status_code = 200 # Range not satisfable, see 4.4 Note
          IO.copy(file, env.response)
        end
      end
    end
  end
end
