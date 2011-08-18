require "./test/helper"

class DummyProxy
  attr_reader :content
  def initialize(content); @content = content; end
end

class AsyncStorageTest < Test::Unit::TestCase
  context "when the async storage engine is chosen" do
    setup do
      rebuild_model :storage => :async,
                    :storage_proxy => DummyProxy,
                    :bucket => "testing",
                    :path => ":attachment/:style/:basename.:extension",
                    :s3_credentials => {
                      'access_key_id' => "12345",
                      'secret_access_key' => "54321"
                    }
    end

    should "be extended by the S3 module" do
      assert Dummy.new.avatar.is_a?(Paperclip::Storage::S3)
    end

    should "be extended by the Async module" do
      assert Dummy.new.avatar.is_a?(Paperclip::Storage::Async)
    end

    should "not be extended by the Filesystem module" do
      assert ! Dummy.new.avatar.is_a?(Paperclip::Storage::Filesystem)
    end

    context "and saved" do
      setup do
        @file = File.new(File.join(File.dirname(__FILE__), 'fixtures', '5k.png'), 'rb')
        @dummy = Dummy.new
        @dummy.avatar = @file
        @dummy.stubs(:id).returns(1)
      end

      teardown { @file.close }

      context "when the storage_proxy is processing?" do
        context "and saved" do
          setup do
            @proxy = DummyProxy.new("content")
            DummyProxy.expects(:processing?).with(:avatar, @dummy, @dummy.avatar.digest).returns(true)
          end

          should "do nothing" do
            assert_nil @dummy.avatar.save
          end
        end
      end

      context "when the storage_proxy is not processing?" do
        context "and saved" do
          setup do
            AWS::S3::S3Object.stubs(:store).with(@dummy.avatar.path, anything, 'testing', :content_type => 'image/png', :access => :public_read)
            DummyProxy.expects(:processing?).with(:avatar, @dummy, @dummy.avatar.digest).returns(false)
            @dummy.avatar.save
          end

          should "succeed" do
            assert true
          end
        end
      end
    end

    context "and to_file is called" do
      setup do
        @file = File.new(File.join(File.dirname(__FILE__), 'fixtures', '5k.png'), 'rb')
        @dummy = Dummy.new
        @dummy.avatar = @file
        @dummy.stubs(:id).returns(1)
      end

      teardown { @file.close }

      context "when the proxy class is not uploaded_to_s3?" do
        setup do
          @proxy = DummyProxy.new("content")
          @proxy.expects(:uploaded_to_s3?).returns(false)
          @proxy.expects(:content)
          DummyProxy.expects(:new).with(:avatar, anything, anything).returns(@proxy)
          @dummy.avatar.queued_for_write.delete(:original)
        end

        should "retrieve content from the proxy and generate a tempfile with the right name" do
          file = @dummy.avatar.to_file
          assert_match /^5k.*\.png$/, File.basename(file.path)
        end
      end

      context "when the proxy class is uploaded_to_s3?" do
        setup do
          @proxy = DummyProxy.new("content")
          @proxy.expects(:uploaded_to_s3?).returns(true)
          @proxy.expects(:content).never
          DummyProxy.expects(:new).with(:avatar, anything, anything).returns(@proxy)
          @dummy.avatar.queued_for_write.delete(:original)
        end

        should "generate a tempfile with the right name" do
          AWS::S3::S3Object.expects(:value).with(@dummy.avatar.path, anything)
          file = @dummy.avatar.to_file
          assert_match /^5k.*\.png$/, File.basename(file.path)
        end
      end
    end
  end
end
