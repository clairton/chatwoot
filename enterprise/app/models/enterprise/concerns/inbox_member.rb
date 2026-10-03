module Enterprise::Concerns::InboxMember
  extend ActiveSupport::Concern

  SIP_URI_REGEX = /\Asips?:[^@\s]+@[^@\s]+\z/

  included do
    # The agent's own extension on a SIP inbox. Each member registers with the PBX under these
    # credentials, so the same person can hold a different extension on every SIP inbox.
    store :data, accessors: [:sip_uri, :sip_password], coder: JSON

    validates :sip_uri, format: { with: SIP_URI_REGEX }, allow_blank: true
    validate :sip_extension_unique_in_inbox, if: -> { sip_extension.present? }
  end

  # The user part of the SIP URI (`sip:1001@pbx.example.com` -> `1001`), which is what a PBX dials.
  def sip_extension
    sip_uri.to_s[/\Asips?:([^@]+)@/, 1]
  end

  private

  # The PBX names the answering agent by extension, so two members cannot share one.
  def sip_extension_unique_in_inbox
    taken = inbox.inbox_members.where.not(id: id).any? { |member| member.sip_extension == sip_extension }
    errors.add(:sip_uri, :taken) if taken
  end
end
