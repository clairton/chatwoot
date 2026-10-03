# A SIP contact has a single identity in the inbox, so any of its threads can carry the call.
class Voice::Provider::Sip::ConversationBuilder < Whatsapp::CallConversationBuilder
  def contact_conversations
    inbox.conversations.where(contact_id: contact.id).order(last_activity_at: :desc)
  end
end
