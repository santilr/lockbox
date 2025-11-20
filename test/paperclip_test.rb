require_relative "test_helper"
require "fileutils"

class PaperclipTest < Minitest::Test
  def setup
    skip unless defined?(Paperclip)
    skip if mongoid?
    cleanup_files
  end

  def teardown
    cleanup_files
    @content = nil
  end

  def test_encrypt
    user = User.create!(paperclip_avatar: uploaded_file)

    assert_equal content, user.paperclip_avatar.download
    refute_equal content, File.binread(user.paperclip_avatar.path)

    user = User.last
    assert_equal content, user.paperclip_avatar.download
    refute_equal content, File.binread(user.paperclip_avatar.path)
  end

  def test_rotate_encryption
    user = User.create!(paperclip_avatar: uploaded_file)
    ciphertext = File.binread(user.paperclip_avatar.path)

    user.paperclip_avatar.rotate_encryption!

    assert_equal content, user.paperclip_avatar.download
    refute_equal ciphertext, File.binread(user.paperclip_avatar.path)
  end

  def test_encrypt_styles
    user = User.create!(paperclip_avatar: uploaded_file)

    assert_equal content, user.paperclip_avatar.download(:thumb)
    refute_equal content, File.binread(user.paperclip_avatar.path(:thumb))
  end

  def test_rotate_styles
    user = User.create!(paperclip_avatar: uploaded_file)
    thumb_ciphertext = File.binread(user.paperclip_avatar.path(:thumb))

    user.paperclip_avatar.rotate_encryption!
    new_thumb_ciphertext = File.binread(user.paperclip_avatar.path(:thumb))

    refute_equal thumb_ciphertext, new_thumb_ciphertext
    assert_equal content, user.paperclip_avatar.download(:thumb)
  end

  def test_download_without_file
    user = User.create!
    assert_nil user.paperclip_avatar.download
  end

  def test_migrate_existing_file
    user = User.create!(paperclip_legacy: uploaded_file)
    path = user.paperclip_legacy.path

    File.binwrite(path, content)
    assert_equal content, user.paperclip_legacy.download

    Lockbox.migrate(User)
    user.reload

    refute_equal content, File.binread(path)
    assert_equal content, user.paperclip_legacy.download
  end

  def test_migrate_plaintext_file
    user = User.create!(paperclip_legacy: uploaded_file)
    path = user.paperclip_legacy.path
    File.binwrite(path, content)

    assert_equal content, user.paperclip_legacy.download

    Lockbox.migrate(User)
    user.reload

    assert_equal content, user.paperclip_legacy.download
  end

  def test_migrate_skips_encrypted_file
    user = User.create!(paperclip_legacy: uploaded_file)
    Lockbox.migrate(User)
    user.reload
    ciphertext = File.binread(user.paperclip_legacy.path)

    Lockbox.migrate(User)
    user.reload

    assert_equal ciphertext, File.binread(user.paperclip_legacy.path)
  end

  def test_file_adapter_encryption
    File.open("test/support/image.png", "rb") do |image|
      user = User.create!(paperclip_avatar: image)
      assert_equal File.binread("test/support/image.png"), user.paperclip_avatar.download
      refute_equal File.binread("test/support/image.png"), File.binread(user.paperclip_avatar.path)
    end
  end

  def test_metadata_columns_remain_plaintext
    user = User.create!(paperclip_avatar: uploaded_file)
    assert_equal content.bytesize, user.paperclip_avatar_file_size
    assert_equal "text/plain", user.paperclip_avatar_content_type
  end

  def test_encrypt_remote_storage
    with_memory_storage do
      user = User.create!(paperclip_avatar: uploaded_file)

      tempfile = user.paperclip_avatar.to_file
      ciphertext = tempfile.read
      tempfile.close!

      refute_equal content, ciphertext
      assert_equal content, user.paperclip_avatar.download
    end
  end

  def test_rotate_remote_storage
    with_memory_storage do
      user = User.create!(paperclip_avatar: uploaded_file)
      old_tempfile = user.paperclip_avatar.to_file
      old_ciphertext = old_tempfile.read
      old_tempfile.close!

      user.paperclip_avatar.rotate_encryption!

      new_tempfile = user.paperclip_avatar.to_file
      new_ciphertext = new_tempfile.read
      new_tempfile.close!

      refute_equal old_ciphertext, new_ciphertext
      assert_equal content, user.paperclip_avatar.download
    end
  end

  private

  def content
    @content ||= "Paperclip #{SecureRandom.hex(6)}"
  end

  def uploaded_file
    file = Tempfile.new(["paperclip", ".txt"])
    file.binmode
    file.write(content)
    file.rewind
    file
  end

  def cleanup_files
    root = File.expand_path("tmp/paperclip", __dir__)
    FileUtils.rm_rf(root)
    FileUtils.mkdir_p(root)
    Paperclip::Storage::Memory.clear_store if defined?(Paperclip::Storage::Memory)
  end

  def with_memory_storage
    previous_storage = Paperclip::Attachment.default_options[:storage]
    Paperclip::Attachment.default_options[:storage] = :memory
    yield
  ensure
    Paperclip::Attachment.default_options[:storage] = previous_storage
  end
end
