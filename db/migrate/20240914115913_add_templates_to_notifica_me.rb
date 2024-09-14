class AddTemplatesToNotificaMe < ActiveRecord::Migration[7.0]
  def change
    add_column :channel_notifica_me, :message_templates, :jsonb, default: '{}', null: false
    add_column :channel_notifica_me, :message_templates_last_updated, :datetime
  end
end
