class DropSolidQueueTables < ActiveRecord::Migration[8.1]
  def up
    # Child tables (FK -> solid_queue_jobs.job_id) must go before the parent.
    drop_table :solid_queue_blocked_executions
    drop_table :solid_queue_claimed_executions
    drop_table :solid_queue_failed_executions
    drop_table :solid_queue_ready_executions
    drop_table :solid_queue_recurring_executions
    drop_table :solid_queue_scheduled_executions

    drop_table :solid_queue_jobs

    drop_table :solid_queue_pauses
    drop_table :solid_queue_processes
    drop_table :solid_queue_recurring_tasks
    drop_table :solid_queue_semaphores
  end

  def down
    raise ActiveRecord::IrreversibleMigration, 'Solid Queue was replaced by Sidekiq; re-run the solid_queue install generator to restore these tables.'
  end
end
