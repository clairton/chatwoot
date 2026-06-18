class Whatsapp::SendOnWhatsappService < Base::SendOnChannelService
  private

  def channel_class
    Channel::Whatsapp
  end

  def perform_reply
    return if message.message_type == :outgoing && message.source_id&.is_present? # is message send by own

    should_send_template_message = template_params.present? || !message.conversation.can_reply?
    if should_send_template_message
      send_template_message
    else
      send_session_message
    end
  end

  def send_template_message
    processor = Whatsapp::TemplateProcessorService.new(
      channel: channel,
      template_params: template_params,
      message: message
    )

    name, namespace, lang_code, processed_parameters = processor.call

    if name.blank?
      message.update!(status: :failed, external_error: 'Template not found or invalid template name')
      return
    end
    template_info = message.conversation.contact_inbox.source_id, {
      name: name,
      namespace: namespace,
      lang_code: lang_code,
      parameters: processed_parameters
    }
    message_id = channel.send_template(phone_number, template_info, message)
    message.update!(source_id: message_id) if message_id.present?
  end

  def phone_number
    uuid_regex = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/
    if uuid_regex.match?(message.conversation.contact_inbox.source_id)
      message.conversation.contact_inbox.contact.phone_number.sub('+', '')
    else
      message.conversation.contact_inbox.source_id
    end
  end

  def send_session_message
    message_id = channel.send_message(phone_number, message)
    message.update!(source_id: message_id) if message_id.present?
  end

  def template_params
    message.additional_attributes && message.additional_attributes['template_params']
  end
end
