class UpdateLastSeenJob < ApplicationJob
  queue_as :default

  def perform(conversation_id, agent_last_seen_at)
    conversation = Conversation.find(conversation_id)
    messages = conversation.messages.to_read(agent_last_seen_at)
    Rails.logger.debug { "Conversation #{conversation_id} with #{messages.size} message(s) to update status to read" }
    messages.each do |message|
      message.update(status: :read)
    end
  end
end
