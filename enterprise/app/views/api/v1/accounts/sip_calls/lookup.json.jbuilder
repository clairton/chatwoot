json.partial! 'api/v1/models/whatsapp_call', call: @call
# The dashboard keys conversations by display id, which is all it can use to open the thread.
json.conversation_display_id @call.conversation.display_id
