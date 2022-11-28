class QueueEntry < DBModel
  belongs_to :contact
  belongs_to :user
  belongs_to :note

  ACTIONS = {
    :attachment_fetch => proc{|qe|
      Attachment.fetch_for_queue_entry(qe)
    },
    :contact_refresh => proc{|qe|
      Contact.refresh_for_queue_entry(qe)
    },
    :signed_post => proc{|qe|
      ActivityStream.signed_post_with_key(self.contact.inbox, self.object_json,
        self.user.activitystream_key_id, self.user.private_key)
    },
  }

  MAX_TRIES = 10

  before_create :assign_first_try

  def object
    @_object ||= JSON.parse(self.object_json)
  end

  def process!
    ok = false

    if !ACTIONS[self.action.to_sym]
      raise "unknown action #{self.action.inspect}"
    end

    if ACTIONS[self.action.to_sym].call(self)
      self.destroy
      return
    end

    if self.tries >= MAX_TRIES
      App.logger.error "[q#{self.id}] too many retries, giving up"
      self.destroy
      return
    end

    self.tries += 1
    self.next_try_at = Time.now + (2 ** (self.tries + 3))
    self.save!

    App.logger.info "[q#{self.id}] failed, retrying at #{self.next_try_at}"
  end

private
  def assign_first_try
    self.tries = 0
    self.next_try_at = Time.now
  end
end
