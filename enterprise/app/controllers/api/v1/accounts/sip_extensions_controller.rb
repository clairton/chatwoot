class Api::V1::Accounts::SipExtensionsController < Api::V1::Accounts::BaseController
  before_action :fetch_inbox

  # Every member's extension, for the inbox settings screen. Passwords are write-only.
  def index
    authorize @inbox, :update?
    render json: { payload: @inbox.inbox_members.includes(:user).map { |member| extension_payload(member) } }
  end

  # A blank password keeps the stored one, so the URI can be edited without retyping it;
  # a blank URI clears the extension altogether.
  def update
    authorize @inbox, :update?
    member = @inbox.inbox_members.find_by!(user_id: params[:id])
    member.sip_uri = params[:sip_uri].presence
    member.sip_password = params[:sip_password] if params[:sip_password].present?
    member.sip_password = nil if member.sip_uri.blank?
    member.save!
    render json: extension_payload(member)
  end

  # The signed-in agent's own credentials, which the browser needs in full to register with the PBX.
  def current
    authorize @inbox, :show?
    member = @inbox.inbox_members.find_by(user_id: Current.user.id)
    render json: {
      url: @inbox.channel.url,
      uri: member&.sip_uri,
      password: member&.sip_password,
      ice_servers: Call.default_ice_servers
    }
  end

  private

  def fetch_inbox
    @inbox = Current.account.inboxes.where(channel_type: 'Channel::Sip').find(params[:inbox_id])
  end

  def extension_payload(member)
    {
      user_id: member.user_id,
      name: member.user.available_name,
      thumbnail: member.user.avatar_url,
      sip_uri: member.sip_uri,
      has_password: member.sip_password.present?
    }
  end
end
