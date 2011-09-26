require './test/helper'

class Dummy; end
class DummyProxy
  def self.processing?(a,b,c) true; end
  def self.enqueue_save(a,b,c) true; end
end

class DelayedTest < Test::Unit::TestCase
  context "Attachment delayed file processing" do
    setup do
      rebuild_model :storage => :async,
                    :storage_proxy => DummyProxy,
                    :bucket => "testing",
                    :path => ":digest/:style.:extension",
                    :s3_credentials => {
                      'access_key_id' => "12345",
                      'secret_access_key' => "54321"
                    }
      @file = File.new(File.join(File.dirname(__FILE__), 'fixtures', '5k.png'), 'rb')
      Dummy.class_eval { process_in_background :avatar }
      @dummy = Dummy.new
      @dummy.avatar.stubs(:save)
    end

    context "when updating the attached file" do
      setup { @dummy.avatar = @file }

      should "tell when an file has changed" do
        assert @dummy.avatar_changed?
      end
    end

    context "on assignment" do
      should "enqueue a job to process the file" do
        @dummy.expects(:enqueue_save_for_avatar)
        @dummy.expects(:enqueue_delete_for_avatar)
        @dummy.expects(:avatar_process_and_upload)
        @dummy.update_attributes(:avatar => @file)
      end

      context "when saving the new file" do
        setup do
          AWS::S3::S3Object.stubs(:exists?).returns(true)
          @paths = @dummy.avatar.paths
          @second_file = File.new(File.join(File.dirname(__FILE__), 'fixtures', '12k.png'), 'rb')
          @new_digest = @dummy.avatar.generate_digest(@second_file)
          @dummy.stubs(:avatar_digest_was).returns(@dummy.avatar.generate_digest(@file))
        end

        context "and the files are different" do
          setup do
            @dummy.stubs(:enqueue_delete_for_avatar)
            @dummy.stubs(:avatar_process_and_upload)
          end

          should "enqueue a job to delete the old file and upload and process a new file" do
            DummyProxy.expects(:enqueue_save).with(:avatar, @dummy, @new_digest)
            @dummy.update_attributes(:avatar => @second_file)
          end
        end

        context "and the files are the same" do
          should "should enqueue a save job" do
            @dummy.update_attributes(:avatar => @file)
            DummyProxy.expects(:enqueue_save)
            @dummy.update_attributes(:avatar => @file)
          end

          should "should not enqueue a delete job" do
            @dummy.update_attributes(:avatar => @file)
            DummyProxy.expects(:enqueue_delete).never
            @dummy.update_attributes(:avatar => @file)
          end
        end
      end

      context "and there is an existing file to delete" do
        setup do
          AWS::S3::S3Object.stubs(:exists?).returns(true)
          @dummy.avatar = @file
          @dummy.stubs(:enqueue_save_for_avatar)
          @dummy.stubs(:avatar_process_and_upload)
          @paths = @dummy.avatar.paths
          @dummy.stubs(:avatar_digest_was).returns(@dummy.avatar.generate_digest(@file))
        end

        context "and the files are different" do
          setup { @second_file = File.new(File.join(File.dirname(__FILE__), 'fixtures', '12k.png'), 'rb') }
          should "enqueue a job to delete the old file and upload and process a new file" do
            DummyProxy.expects(:enqueue_delete).with(:avatar, @dummy, @paths)
            @dummy.update_attributes(:avatar => @second_file)
          end
        end

        context "and the files are the same" do
          should "not enqueue a job to delete the file or upload and process a new file" do
            DummyProxy.expects(:enqueue_delete).with(:avatar, @dummy, @paths).never
            @dummy.update_attributes(:avatar => @file)
          end
        end
      end

      context "and there is no existing file" do
        setup do
          AWS::S3::S3Object.stubs(:exists?).returns(false)
          @dummy.stubs(:enqueue_save_for_avatar)
          @dummy.avatar = nil
        end

        should "not enqueue a job to delete the old file" do
          DummyProxy.expects(:enqueue_delete).never
          @dummy.update_attributes(:avatar => @second_file)
        end
      end

      should "put the file into the storage proxy" do
        DummyProxy.expects(:processing?).with(:avatar, @dummy, anything).returns(false)
        DummyProxy.expects(:enqueue_save).with(:avatar, @dummy, anything)
        DummyProxy.expects(:process!).with(:avatar, @dummy, anything, anything)
        @dummy.update_attributes(:avatar => @file)
      end
    end
  end
end