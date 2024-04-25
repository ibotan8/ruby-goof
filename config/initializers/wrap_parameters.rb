# frozen_string_literal: true

ActiveAdmin.register App do
  actions :index, :show

  menu label: I18n.t('active_admin.menu.app'), parent: I18n.t('active_admin.menu.settings')

  config.batch_actions = false

  filter :name
  filter :auth0_client_id
  filter :is_first_party
  filter :source
  filter :created_at
  filter :database_reference

  action_item(:new_third_party_app, only: :index, if: proc { policy(App).create? }) do
    link_to I18n.t('admin.apps.index.button.create.third_party'), new_auth0_third_party_app_path
  end

  action_item(:new_first_party_app, only: :index, if: proc { policy(App).create? }) do
    link_to I18n.t('admin.apps.index.button.create.first_party'), new_auth0_first_party_app_path
  end

  action_item(:sync_app, only: :index, if: proc { policy(::App).sync? }) do
    link_to I18n.t('admin.apps.index.button.sync'), auth0_apps_syncs_path, method: :create
  end

  action_item(:edit_app, only: [:show], if: proc { app.is_first_party? && policy(app).edit? }) do
    link_to I18n.t('admin.apps.show.button.edit'), edit_auth0_app_path
  end

  action_item(:edit_third_party_app, only: [:show], if: proc { !app.is_first_party? && policy(app).edit? }) do
    link_to I18n.t('admin.apps.show.button.edit'), edit_auth0_third_party_app_path
  end

  action_item(:sync_app_on_auth0, only: :show, if: proc { policy(app).sync_app_on_auth0? && app.source == ::App::ALPHONSE }) do
    link_to 'Sync Auth0', sync_app_on_auth0_admin_app_path(app)
  end

  action_item(:audit_trail, only: :show) do
    link_to_audit_trail(resource)
  end

  member_action :sync_app_on_auth0, method: :get do
    app = App.find(params[:id])

    authorize app

    begin
      Auth0::SyncApp.call(app)
      app.app_grants.each { |app_grant| Auth0::SyncAppGrant.call(app_grant) }
      flash[:notice] = 'Application synchronisée sur Auth0.'
    rescue StandardError => e
      Sentry.capture_exception(e)
      flash[:error] = "Une erreur s'est produite : #{e.message}"
    end

    redirect_to admin_app_path(app)
  end

  index do
    column :name
    column :display_name
    column :url
    column :is_first_party
    column :source
    column :created_at

    actions
  end

  show do |app|
    columns do
      column do
        panel t('admin.apps.show.panel.details') do
          attributes_table_for app do
            row :name
            row :is_first_party
            row :publisher_workspace
            row :human_purpose
            row :support_email
            row :domains
            row :fhir_references
            row :database_reference
            row :databases_references do
              "<ul>#{app.databases_references.map { |db_ref| "<li>#{db_ref}</li>" }.join}</ul>".html_safe # rubocop:disable Rails/OutputSafety
            end
            row :sending_prohibited do
              !app.sending_prohibited
            end
            row :for_external_users
            row :for_internal_users
            row :source
            row :created_at
            row :updated_at
            row :lock_version
          end
        end

        panel t('admin.apps.show.panel.identities') do
          if policy(IdentityApp.new(app: app)).create?
            header_action link_to(t('admin.apps.show.button.add_identity'), new_auth0_app_identity_app_path(app_id: app.id), class: 'button')
          end
          table_for app.identities do
            column(:name)
            column(:lifen_reference)
            if policy(IdentityApp).destroy?
              column('') do |identity|
                link_to(
                  t('admin.apps.show.button.detach_identity'),
                  auth0_app_identity_app_path(app_id: app.id, id: identity.id),
                  method: :delete,
                  data: { confirm: t('.detach_app_identity.confirm') },
                )
              end
            end
          end

          data_stream_apps = DataStreamApp.where(app: app).includes(data_stream: :identity)

          panel t('admin.apps.show.panel.data_stream_apps') do
            table_for data_stream_apps do
              column(:identity) do |data_stream_app|
                link_to(data_stream_app.data_stream.identity.name, admin_identities_path(q: { id_eq: data_stream_app.data_stream.identity_id }))
              end
              column(:database_reference)
              column(:allowed_uf_codes, :allowed_uf_codes_display)
              column(:type_code) { |data_stream_app| data_stream_app.data_stream.type_code }
              column(:direction) { |data_stream_app| data_stream_app.data_stream.direction }
              column('') { |data_stream_app| link_to t('active_admin.action_items.show'), admin_data_stream_app_path(data_stream_app) }
            end
          end
        end

        panel t('admin.apps.show.panel.mss_telecoms') do
          if policy(AppMssTelecom.new(app: app)).create?
            header_action link_to(t('admin.apps.show.button.add_telecom'), new_auth0_app_app_mss_telecom_path(app_id: app.id), class: 'button')
          end
          table_for app.app_mss_telecoms do
            column(:value)
            column(&:organization_reference)

            if policy(AppMssTelecom).destroy?
              column('') do |identity|
                link_to(
                  t('admin.apps.show.button.destroy_telecom'),
                  auth0_app_app_mss_telecom_path(app_id: app.id, id: identity.id),
                  method: :delete,
                )
              end
            end
          end
        end
      end

      column do
        panel t('admin.apps.show.panel.auth_config') do
          attributes_table_for app do
            row :managed_by_alphonse
            row :auth0_client_id
            if Rails.env.staging? || Rails.env.development? || Rails.env.test?
              row :auth0_client_secret do |app|
                render partial: 'admin/apps/auth0_secrets', locals: { app: app }
              end
            end
            row :human_user_auth_type
            row :human_client_auth_type
            row :initiate_login_uri
            row :callbacks
            row :allowed_logout_urls
            row :web_origins
          end

          if app.auth0_client_id
            text_node link_to(t('admin.apps.show.button.show_on_auth0'), app.auth0_link, target: :_blank, class: 'button', rel: :noopener)
          end
        end

        if app.user_auth?
          panel t('admin.apps.show.panel.business_config') do
            attributes_table_for app do
              row :display_name
              row :url
              row :icon_url
              row :initiate_login_uri
            end
          end

          panel t('admin.apps.show.panel.user_auth') do
            attributes_table_for app do
              row :second_factor_required
              row :identity_required
              row :telecom_required
              row :workspace_required
              row :email_validation_required
            end
          end
        end

        if app.client_auth?
          panel t('admin.apps.show.panel.app_grants') do
            table_for app.app_grants do
              column :audience
              column :scopes
            end
          end
        end
      end
    end
  end
end
