class Api::V1::Accounts::CampaignsController < Api::V1::Accounts::BaseController
  before_action :campaign, except: [:index, :create]
  before_action :check_authorization

  def index
    @campaigns = Current.account.campaigns
  end

  def show; end

  def create
    @campaign = Current.account.campaigns.create!(campaign_params)
  end

  def update
    @campaign.update!(campaign_params)
  end

  def destroy
    @campaign.destroy!
    head :ok
  end

  private

  def campaign
    @campaign ||= Current.account.campaigns.find_by(display_id: params[:id])
  end

  def campaign_params
    fields = [:title, :description, :message, :enabled, :trigger_only_during_business_hours, :inbox_id, :sender_id, :scheduled_at]
    fields << { trigger_rules: {} }
    fields << if Inbox.find(params[:inbox_id])&.channel&.provider == 'unoapi'
                { audience: [] }
              else
                { audience: [:type, :id] }
              end
    params.require(:campaign).permit(fields)
  end
end
