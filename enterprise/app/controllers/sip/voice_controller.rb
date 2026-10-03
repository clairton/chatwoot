# Webhook the PBX calls to report call lifecycle events for a SIP inbox. The token in the path is
# the channel's secret, so it both identifies the inbox and authenticates the PBX.
class Sip::VoiceController < ApplicationController
  before_action :set_inbox!

  def events
    event = params.permit(:event, :call_id, :from, :name, :extension, :duration)
    event.require([:event, :call_id])
    event.require(:from) if event[:event] == 'ringing'
    return render_could_not_create_error('Unknown event') unless Voice::Provider::Sip::EventService::STATUS_MAP.key?(event[:event])

    render json: Voice::Provider::Sip::EventService.new(inbox: @inbox, params: event).perform
  end

  private

  def set_inbox!
    channel = Channel::Sip.find_by!(webhook_token: params[:token])
    raise ActiveRecord::RecordNotFound, 'Voice not enabled for this inbox' unless channel.voice_enabled?

    @inbox = channel.inbox
  end
end
