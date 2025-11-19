return unless defined?(Paperclip)

require "fileutils"

paperclip_path = File.expand_path("../../tmp/paperclip", __dir__)
FileUtils.mkdir_p(paperclip_path)

Paperclip::Attachment.default_options.merge!(
  path: "#{paperclip_path}/:class/:attachment/:id_partition/:style/:filename",
  url: "#{paperclip_path}/:class/:attachment/:id_partition/:style/:filename",
  use_timestamp: false
)

Paperclip.options[:log] = false

module Paperclip
  class Noop < Processor
    def make
      file
    end
  end
end
