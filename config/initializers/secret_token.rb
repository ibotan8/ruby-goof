# frozen_string_literal: true

ActiveAdmin.register PaperTrail::Version do
  menu parent: I18n.t('active_admin.menu.monitoring'), label: 'Audit Trail'

  actions :index

  controller do
    # by default ActiveAdmin returns the collection PaperTrail::Version.all
    # we overwrite the method scoped_collection in order to filter the collection on custom params
    def scoped_collection
      if action_name == 'index'
        if (whodunnit_search_value = params.dig(:q, :whodunnit_eq)&.strip)
          # we transform the whodunnit params into a proper id if possible
          # this way can filter with the user email, or the app name
          if (user = User.find_by(email: whodunnit_search_value))
            params[:q][:whodunnit_eq] = user.lifen_id
          elsif (app = App.find_by(name: whodunnit_search_value))
            params[:q][:whodunnit_eq] = app.auth0_client_id
          end
        end

        if params[:class] && params[:id] # These parameters are passed by ActiveAdminHelper#link_to_audit_trail
          flash.now.notice = "Un filtre non visible dans le panel de droite est actuellement appliqué, il vient des paramètres passés dans l'url. Pour le supprimer, cliquez #{view_context.link_to 'ici', admin_paper_trail_versions_path}.".html_safe # rubocop:disable Rails/OutputSafety
          # we want to show the versions of the object itself and the versions of its children
          end_of_association_chain.where(
            '(item_type = :class AND item_id = :id) '\
            'OR (parent_class = :class AND parent_id = :id)'\
            'OR (coparent_class = :class AND coparent_id = :id)',
            { class: params['class'], id: params['id'].to_i },
          )
        else
          super
        end
      end
    end
  end

  index pagination_total: false do
    column :link do |version|
      version.item || 'Deleted'
    end
    column :event
    column :item_type
    column :item_id
    column :parent_link, &:parent
    column 'ParentClass#id', &:parent_class_and_id
    column :coparent_link, &:coparent
    column 'CoparentClass#id', &:coparent_class_and_id
    column :whodunnit, &:whodunnit_to_display
    column :source
    column :job_name
    column(:created_at) do |version|
      version.created_at.strftime('%d/%m/%Y %kh%M:%S:%L')
    end
    column :object_changes, &:object_changes_to_display
  end

  filter :event, as: :select, collection: PaperTrail::Version::EVENTS # avoid a slow select distinct query
  filter :item_type, as: :select, collection: ApplicationRecord.descendants.map(&:name).sort # avoid a slow select distinct query
  filter :item_id_eq, label: I18n.t('activerecord.attributes.paper_trail/version.item_id')
  filter :source, filters: [:eq]
  filter :job_name, filters: [:eq]
  filter :whodunnit, filters: [:eq]
  filter :created_at, as: :date_range
end
