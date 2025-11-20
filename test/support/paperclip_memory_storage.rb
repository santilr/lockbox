# Minimal in-memory Paperclip storage to simulate a remote service (like GCS)
module Paperclip
  module Storage
    module Memory
      def self.extended(base); end

      def self.store
        @memory_store ||= {}
      end

      def self.clear_store
        store.clear
      end

      def exists?(style = default_style)
        Memory.store.key?(memory_store_key(style))
      end

      def to_file(style = default_style, &block)
        return @queued_for_write[style] if @queued_for_write[style]

        data = Memory.store[memory_store_key(style)]
        return nil unless data

        tempfile = Tempfile.new(["paperclip-memory", "-#{style}"])
        tempfile.binmode
        tempfile.write(data)
        tempfile.rewind
        block_given? ? yield(tempfile) : tempfile
      end

      def copy_to_local_file(style, dest_path)
        data = Memory.store[memory_store_key(style)]
        return unless data
        File.binwrite(dest_path, data)
      end

      def flush_writes
        @queued_for_write.each do |style, file|
          io = file.respond_to?(:to_file) ? file.to_file : file
          io.rewind if io.respond_to?(:rewind)
          Memory.store[memory_store_key(style)] = io.read
          io.rewind if io.respond_to?(:rewind)
        end
        @queued_for_write.clear
      end

      def flush_deletes
        @queued_for_delete.each do |style|
          Memory.store.delete(memory_store_key(style))
        end
        @queued_for_delete.clear
      end

      def path(style = default_style)
        "memory://#{memory_store_key(style)}"
      end

      private

      def memory_store_key(style)
        [
          instance.class.name,
          instance.id || object_id,
          name,
          style
        ].join("-")
      end
    end
  end
end
