# Applies a call lifecycle event reported by the PBX. `ringing` announces an inbound call and is
# answered with what the PBX should do next; every other event moves an existing call along.
class Voice::Provider::Sip::EventService
  pattr_initialize [:inbox!, :params!]

  STATUS_MAP = {
    'ringing' => 'ringing',
    'answered' => 'in_progress',
    'completed' => 'completed',
    'no_answer' => 'no_answer',
    'busy' => 'no_answer',
    'canceled' => 'no_answer',
    'rejected' => 'rejected',
    'failed' => 'failed'
  }.freeze
  E164_REGEX = /\A\+[1-9]\d{1,14}\z/

  def perform
    return ring if status == 'ringing'

    call = inbox.calls.sip.find_by!(provider_call_id: params[:call_id])
    agent = answering_agent(call)
    agent ? accept(call, agent) : apply_status(call)
    { call_id: call.provider_call_id, status: call.display_status }
  end

  private

  def status
    STATUS_MAP.fetch(params[:event])
  end

  def ring
    return { action: 'reject' } unless inbox.channel.inbound_calls_enabled?

    call = Voice::InboundCallBuilder.perform!(inbox: inbox, call_sid: params[:call_id], provider: :sip, caller: caller_identity)
    { action: 'ring', call_id: call.provider_call_id, conversation_id: call.conversation.display_id, extensions: extensions_to_ring(call) }
  end

  # A withheld caller ID arrives as a label such as `anonymous`, which still identifies the
  # thread but is not a phone number the contact can be saved with.
  def caller_identity
    from = params[:from].to_s
    phone_number = from if from.match?(E164_REGEX)
    { source_ids: [from], contact_attributes: { name: params[:name].presence || from, phone_number: phone_number }.compact }
  end

  # Ring the assignee, else the online members, else every member; always skipping whoever has no extension.
  def extensions_to_ring(call)
    members = inbox.inbox_members
    [members.where(user_id: call.conversation.assignee_id), inbox.available_agents, members].each do |candidates|
      extensions = candidates.filter_map(&:sip_extension)
      return extensions if extensions.any?
    end
    []
  end

  # Only the pickup of an inbound call names an agent.
  def answering_agent(call)
    return unless status == 'in_progress' && call.incoming? && params[:extension].present?

    inbox.inbox_members.find { |member| member.sip_extension == params[:extension] }&.user
  end

  # Same path as the agent's own accept, so the browser and the PBX leave the call, its message and
  # the conversation in the same state whichever of them reports the pickup first.
  def accept(call, agent)
    Voice::Provider::Sip::CallService.new(call: call, agent: agent).accept
  rescue Voice::CallErrors::AlreadyAccepted, Voice::CallErrors::CallAlreadyEnded
    # A repeated or late answered event must not disturb a call that has moved on.
  end

  def apply_status(call)
    Voice::CallStatus::Manager.new(call: call).process_status_update(status, duration: params[:duration].presence&.to_i)
    # The manager ignores an event the call has already moved past (the agent hung up first, for instance).
    return unless call.saved_change_to_status?

    if call.terminal?
      call.update!(end_reason: params[:event])
      call.broadcast_voice_call_event(:ended, status: call.display_status)
    elsif call.incoming?
      call.broadcast_voice_call_event(:accepted, accepted_by_agent_id: call.accepted_by_agent_id)
    end
  end
end
