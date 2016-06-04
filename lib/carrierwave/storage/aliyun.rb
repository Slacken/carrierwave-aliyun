require 'aliyun/oss'
require 'carrierwave'
require 'uri'

module CarrierWave
  module Storage
    class Aliyun < Abstract
      class Connection
        PATH_PREFIX = %r{^/}

        def initialize(uploader)
          @uploader = uploader
          @aliyun_access_id    = uploader.aliyun_access_id
          @aliyun_access_key   = uploader.aliyun_access_key
          @aliyun_bucket       = uploader.aliyun_bucket
          @aliyun_area         = uploader.aliyun_area || 'cn-hangzhou'
          @aliyun_private_read = uploader.aliyun_private_read

          # Host for get request
          @aliyun_host = uploader.aliyun_host || "http://#{@aliyun_bucket}.oss-#{@aliyun_area}.aliyuncs.com"

          unless @aliyun_host.include?('//')
            fail "config.aliyun_host requirement include // http:// or https://, but you give: #{@aliyun_host}"
          end
        end

        # 上传文件
        # params:
        # - path - remote 存储路径
        # - file - CarrierWave::SanitizedFile
        # - options:
        #   - content_type - 上传文件的 MimeType，默认 `image/jpg`
        # returns:
        # 图片的下载地址
        def put(path, file, options = {})
          path.sub!(PATH_PREFIX, '')
          opts = {
            content_type: options[:content_type] || 'image/jpg',
            file: file.path
          }
          private_client.put_object(path, opts)
          path_to_url(path)
        end

        # 读取文件
        # params:
        # - path - remote 存储路径
        # returns: Aliyun::OSS::Object
        def get(path, &block)
          path.sub!(PATH_PREFIX, '')
          private_client.get_object(path){ |content| yield content if block_given?}
        end

        # 删除 Remote 的文件
        #
        # params:
        # - path - remote 存储路径
        #
        # returns:
        # 图片的下载地址
        def delete(path)
          path.sub!(PATH_PREFIX, '')
          private_client.delete_object(path)
          path_to_url(path)
        end

        ##
        # 根据配置返回完整的上传文件的访问地址
        def path_to_url(path)
          [@aliyun_host, path].join('/')
        end

        # 私有空间访问地址，会带上实时算出的 token 信息
        # 有效期 3600s
        def private_get_url(path)
          path.sub!(PATH_PREFIX, '')
          public_client.object_url(path, true, 3600)
        end

        private

        def public_client
          if defined?(@_public_client)
            @_public_client
          else
            @_public_client = oss_client(false)
          end
        end

        def private_client
          if !@uploader.aliyun_internal
            public_client
          elsif defined?(@_private_client)
            @_private_client
          else
            @_private_client = oss_client(true)
          end
        end

        def oss_client(is_internal = false)
          client = ::Aliyun::OSS::Client.new(
            endpoint: (is_internal ? "oss-#{@aliyun_area}-internal.aliyuncs.com" : "oss-#{@aliyun_area}.aliyuncs.com"),
            access_key_id: @aliyun_access_id,
            access_key_secret: @aliyun_access_key
            )
          client.get_bucket(@aliyun_bucket)
        end

        # def oss_client
        #   return @oss_client if defined?(@oss_client)
        #   opts = {
        #     host: "oss-#{@aliyun_area}.aliyuncs.com",
        #     bucket: @aliyun_bucket
        #   }
        #   @oss_client = ::Aliyun::Oss::Client.new(@aliyun_access_id, @aliyun_access_key, opts)
        # end

        # def oss_upload_client
        #   return @oss_upload_client if defined?(@oss_upload_client)

        #   if @uploader.aliyun_internal
        #     host = "oss-#{@aliyun_area}-internal.aliyuncs.com"
        #   else
        #     host = "oss-#{@aliyun_area}.aliyuncs.com"
        #   end

        #   opts = {
        #     host: host,
        #     bucket: @aliyun_bucket
        #   }

        #   @oss_upload_client = ::Aliyun::Oss::Client.new(@aliyun_access_id, @aliyun_access_key, opts)
        # end
      end

      class File < CarrierWave::SanitizedFile
        ##
        # Returns the current path/filename of the file on Cloud Files.
        #
        # === Returns
        #
        # [String] A path
        #
        attr_reader :path

        def initialize(uploader, base, path)
          @uploader = uploader
          @path     = URI.encode(path)
          @base     = base
        end

        ##
        # Reads the contents of the file from Cloud Files
        #
        # === Returns
        #
        # [String] contents of the file
        #
        def read
          body = ""
          object = oss_connection.get(@path){|chunk| body << chunk}
          @headers = object.headers
          body
        end

        ##
        # Remove the file from Cloud Files
        #
        def delete
          oss_connection.delete(@path)
          true
        rescue => e
          # If the file's not there, don't panic
          puts "carrierwave-aliyun delete file failed: #{e}"
          nil
        end

        def url
          if @uploader.aliyun_private_read
            oss_connection.private_get_url(@path)
          else
            oss_connection.path_to_url(@path)
          end
        end

        def content_type
          headers[:content_type]
        end

        def content_type=(new_content_type)
          headers[:content_type] = new_content_type
        end

        def store(file, opts = {})
          oss_connection.put(@path, file, opts)
        end

        private

        def headers
          @headers ||= {}
        end

        def connection
          @base.connection
        end

        def oss_connection
          return @oss_connection if defined? @oss_connection

          @oss_connection = CarrierWave::Storage::Aliyun::Connection.new(@uploader)
        end
      end

      # file: CarrierWave::SanitizedFile
      def store!(file)
        f = CarrierWave::Storage::Aliyun::File.new(uploader, self, uploader.store_path)
        f.store(file, content_type: file.content_type)
        f
      end

      def retrieve!(identifier)
        CarrierWave::Storage::Aliyun::File.new(uploader, self, uploader.store_path(identifier))
      end
    end
  end
end
