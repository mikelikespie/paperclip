module Delayed
  def process_in_background(name)
    define_method "#{name}_changed?" do
      send(:"#{name}").try(:dirty?)
    end

    define_method "halt_processing_for_#{name}" do
      return unless send(:"#{name}_changed?")
      false
    end

    define_method "enqueue_save_for_#{name}" do
      return unless send(:"#{name}_changed?")
      send(name).storage_proxy.enqueue_save(:"#{name}", self, send(:"#{name}_digest"))
    end

    define_method "enqueue_delete_for_#{name}" do
      return unless send(:"#{name}_changed?")
      old_digest, new_digest = send(:"#{name}_digest_was"), send(:"#{name}_digest")
      old_file_type, new_file_type = send(:"#{name}_content_type_was"), send(:"#{name}_content_type")
      return if (old_digest == new_digest) || old_digest.blank?
      send(name).storage_proxy.enqueue_delete(:"#{name}", self, send(name).old_paths)
    end

    define_method "#{name}_process_and_upload" do
      return unless send(:"#{name}_changed?")
      return if send(name).storage_proxy.processing?(:"#{name}", self, send(:"#{name}_digest"))
      send(name).storage_proxy.process!(:"#{name}", self, send(:"#{name}_digest"), send(name).queued_for_write[:original])
    end

    self.send("before_#{name}_post_process", :"halt_processing_for_#{name}")

    before_save :"enqueue_delete_for_#{name}"
    before_save :"#{name}_process_and_upload"
    after_save :"enqueue_save_for_#{name}"
  end
end
