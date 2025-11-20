module Lockbox
  module PaperclipExtensions
    module Attachment
      def save(*args, **kwargs, &block)
        lockbox_encrypt_queued_files if lockbox_paperclip_options
        super
      end

      def download(style = default_style)
        style = style.to_sym
        return unless exists?(style)

        data = lockbox_download(style, allow_unencrypted: lockbox_paperclip_migrating?)
        if block_given?
          io = StringIO.new(data)
          yield io
        else
          data
        end
      end

      def rotate_encryption!
        options = lockbox_paperclip_options
        raise Lockbox::Error, "Not encrypted" unless options

        lockbox_rewrite_styles(options)

        true
      end

      def lockbox_paperclip_migrating?
        options = lockbox_paperclip_options
        options && options[:migrating]
      end

      def lockbox_encrypted_style?(style = :original)
        options = lockbox_paperclip_options
        return false unless options && exists?(style)
        lockbox_decrypt_data(style, options, allow_unencrypted: false)
        true
      rescue Lockbox::DecryptionError
        false
      end

      private

      def lockbox_encrypt_queued_files
        box = lockbox_build_box(lockbox_paperclip_options)

        # Read all data first to prevent closed stream errors
        # when Paperclip runs processors
        files_to_encrypt = {}
        @queued_for_write.each do |style, file|
          files_to_encrypt[style] = {
            data: lockbox_read_from_adapter(file),
            filename: lockbox_filename_for(file, style),
            content_type: file.respond_to?(:content_type) ? file.content_type : nil
          }
        end

        ActiveSupport::Notifications.instrument("encrypt_file.lockbox", {name: name}) do
          files_to_encrypt.each do |style, file|
            ciphertext = box.encrypt(file[:data])
            io = Lockbox::IO.new(ciphertext)
            io.original_filename = file[:filename]
            io.content_type = file[:content_type]
            @queued_for_write[style] = Paperclip.io_adapters.for(io, @options[:adapter_options])
          end
        end
      end

      def lockbox_rewrite_styles(options)
        box = lockbox_build_box(options)
        wrote = false

        lockbox_style_names.each do |style|
          next unless exists?(style)

          data = lockbox_download(style, allow_unencrypted: true)
          next unless data
          ciphertext = box.encrypt(data)

          io = Lockbox::IO.new(ciphertext)
          io.original_filename = lockbox_style_filename(style)
          io.content_type = content_type || "application/octet-stream"

          @queued_for_write[style] = Paperclip.io_adapters.for(io, @options[:adapter_options])
          wrote = true
        end

        lockbox_notify("encrypt_file") { flush_writes } if wrote
      end

      def lockbox_download(style, allow_unencrypted: false)
        options = lockbox_paperclip_options
        return lockbox_raw_data(style) unless options

        lockbox_decrypt_data(style, options, allow_unencrypted: allow_unencrypted)
      end

      def lockbox_decrypt_data(style, options, allow_unencrypted:)
        data = lockbox_raw_data(style)
        return unless data

        Lockbox::Utils.decrypt_result(instance, name, options, data)
      rescue Lockbox::DecryptionError
        raise unless allow_unencrypted
        data
      end

      def lockbox_raw_data(style)
        style = style.to_sym
        file_path = path(style) rescue nil
        return File.binread(file_path) if file_path && File.exist?(file_path)

        if respond_to?(:to_file)
          file = to_file(style)
          return lockbox_read_from_adapter(file) if file
        end

        target = lockbox_style_target(style)
        adapter = Paperclip.io_adapters.for(target, @options[:adapter_options])
        lockbox_read_from_adapter(adapter)
      end

      def lockbox_read_from_adapter(adapter)
        return unless adapter

        file = adapter.respond_to?(:to_file) ? adapter.to_file : adapter

        begin
          file.rewind if file.respond_to?(:rewind)
          content = file.read
          # Rewind again for other processors that might need to read the stream
          file.rewind if file.respond_to?(:rewind)
          content
        rescue IOError
          # Some adapters expose a path even if the underlying IO is closed
          if adapter.respond_to?(:path) && adapter.path
            File.binread(adapter.path)
          else
            raise
          end
        end
      end

      def lockbox_build_box(options)
        Lockbox::Utils.build_box(instance, options, Lockbox::Utils.table_name(instance), name)
      end

      def lockbox_style_names
        [:original, *styles.keys].uniq
      end

      def lockbox_style_target(style)
        style == :original ? self : styles.fetch(style)
      end

      def lockbox_filename_for(adapter, style)
        return adapter.original_filename if adapter.respond_to?(:original_filename) && adapter.original_filename
        lockbox_style_filename(style)
      end

      def lockbox_style_filename(style)
        if style == :original
          original_filename
        else
          [style, original_filename].compact.join("_")
        end
      end

      def lockbox_paperclip_options
        Lockbox::Utils.encrypted_options(instance, name)
      end

      def lockbox_notify(event)
        ActiveSupport::Notifications.instrument("#{event}.lockbox", {name: name}) do
          yield
        end
      end
    end

    def self.attach!
      return if @attached
      return unless defined?(Paperclip::Attachment)

      Paperclip::Attachment.prepend(Attachment)
      @attached = true
    end
  end
end
