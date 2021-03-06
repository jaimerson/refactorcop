class ProjectsController < ApplicationController
  layout 'with_small_header'

  def show
    @project_details = ProjectDetails.new({
      username: params.fetch(:username, ''),
      name:     params.fetch(:name, ''),
      severity: params[:severity],
      page:     params[:page],
    })
    if @project_details.exists?
      render
    else
      attempt_project_import_and_redirect
    end
  end

  def send_cops
    project = Project.find_by_id!(params[:id])
    if project.rubocop_running?
      redirect_to_project(project, flash: { notice: "Cops already sent!" })
    else
      RubocopWorker.perform_async(project.id)
      redirect_to_project(project, flash: {
        notice: "Cops sent! The results should be here within a couple of minutes."
      })
    end
  end

  def random
    project = Project.where("rubocop_offenses_count > 0").order("RANDOM()").first
    redirect_to_project(project)
  end

  def not_found
    render status: :not_found
  end

  private

  def redirect_to_project(project, extra_opts = {})
    opts = extra_opts.merge({
      action: "show",
      username: project.username,
      name: project.name
    })
    flashes = opts.delete(:flash)
    redirect_to(opts, {flash: flashes})
  end

  def attempt_project_import_and_redirect
    gh = GithubProject.new(name: @project_details.name, username: @project_details.username)
    if !gh.exists?
      redirect_to action: "not_found", flash: { error: "Could not find that project '#{@project_details.full_name}'" }
      return
    end
    if !gh.contains_ruby?
      redirect_to root_path, flash: { error: "This project does not seem to contain a significant amount of ruby code." }
      return
    end
    save_and_redirect_to_project gh.to_project
  end

  def save_and_redirect_to_project(project)
    project.save!
    RubocopWorker.perform_async(project.id)
    redirect_to_project(project)
  end
end
