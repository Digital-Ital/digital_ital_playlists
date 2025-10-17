class Admin::SchedulerController < Admin::BaseController
  def index
    @paused = SchedulerSetting.paused?
    @quick_updates = SchedulerSetting.quick_updates?
  end
  
  def pause
    SchedulerSetting.pause!
    redirect_to admin_scheduler_path, notice: "Scheduler paused. No more automatic updates will run."
  end
  
  def unpause
    SchedulerSetting.unpause!
    redirect_to admin_scheduler_path, notice: "Scheduler unpaused. Automatic updates will resume."
  end
  
  def toggle_quick_updates
    if SchedulerSetting.quick_updates?
      SchedulerSetting.disable_quick_updates!
      redirect_to admin_scheduler_path, notice: "Quick Updates disabled. Back to hourly updates."
    else
      SchedulerSetting.enable_quick_updates!
      redirect_to admin_scheduler_path, notice: "Quick Updates enabled. Updates will run every 15 minutes."
    end
  end
end
