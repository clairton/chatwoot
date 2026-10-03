# Agent-facing API for SIP calls. It reuses the WhatsApp call endpoints and only swaps the parts
# that talk to Meta: the PBX carries the call, so `initiate` records the call and hands back the
# id the browser then puts on its INVITE (X-Chatwoot-Call-Id) instead of dialling a provider.
class Api::V1::Accounts::SipCallsController < Api::V1::Accounts::WhatsappCallsController
  # An incoming INVITE only carries the id the PBX assigned, so the browser resolves the call from it.
  def lookup
    @call = Current.account.calls.sip.find_by!(provider_call_id: params[:call_id])
    authorize @call.conversation, :show?
  end

  private

  def call_service
    @call_service ||= Voice::Provider::Sip::CallService.new(call: @call, agent: Current.user)
  end

  def set_call
    @call = Current.account.calls.sip.find(params[:id])
    authorize @call.conversation, :show?
  end

  def conversation_builder
    @conversation_builder ||= Voice::Provider::Sip::ConversationBuilder.new(inbox: @inbox, contact: @contact, user: Current.user)
  end

  def ensure_calling_enabled
    channel = @inbox.channel
    return if channel.is_a?(Channel::Sip) && channel.voice_enabled?

    render_could_not_create_error(I18n.t('errors.whatsapp.calls.not_enabled'))
  end

  # The browser negotiates media with the PBX, so there is no SDP offer to require.
  def ensure_sdp_offer; end

  def call_recipient
    @contact.phone_number
  end

  def create_outbound_call
    # A reused thread unassigned at click time is claimed for the caller (wins over auto-assignment); a
    # fresh thread is created already assigned to the caller.
    claim_for_caller = @conversation.present? && @conversation.assigned_entity.nil?

    @conversation = open_conversation!
    @conversation.with_lock { @conversation.update!(assignee: Current.user) } if claim_for_caller

    Current.account.calls.create!(
      provider: :sip, inbox: @conversation.inbox, conversation: @conversation, contact: @conversation.contact,
      provider_call_id: SecureRandom.uuid, direction: :outgoing, status: 'ringing', accepted_by_agent_id: Current.user.id
    )
  end
end
