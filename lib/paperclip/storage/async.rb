module Paperclip
  module Storage
    module Async
      def self.extended(base)
        base.extend(Paperclip::Storage::S3)
        base.class_eval { attr_reader :proxy_class }
        base.instance_eval { @proxy_class = @options[:proxy_class] }
      end

      include Paperclip::Storage::S3

      def save
        return if proxy_class.processing?(name, instance)
        super
      end

      def paths
        [:original, *styles.keys].uniq.map { |style| path(style) }.compact
      end

      def to_file(style = default_style)
        return @queued_for_write[style] if @queued_for_write[style]
        return super unless (proxy = proxy_class.new(name, instance)).processing?
        file_name = instance.send(:"#{name}_file_name")
        log("  \e[32m\e[1m\e[4mAsync paperclip file name:\e[0m   #{file_name}")
        Tempfile.new([File.basename(file_name), File.extname(file_name)]).tap do |tmp|
          tmp.write(proxy.content)
          tmp.rewind
        end
      end

      def url(style = default_style, include_updated_timestamp = true)
        proxy_class.processing?(:"#{@name}", @instance) ? interpolate(@default_url, style) : super
      end
    end
  end
end
