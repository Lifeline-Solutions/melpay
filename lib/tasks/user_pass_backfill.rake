namespace :user_pass do
  desc 'Backfill `user_pass` for users that are missing it (safe, batched).'
  task backfill: :environment do
    require 'securerandom'

    batch_size = ENV.fetch('BATCH_SIZE', 500).to_i
    puts "Starting user_pass backfill (batch_size=#{batch_size})"

    User.where(user_pass: [nil, '']).find_in_batches(batch_size: batch_size) do |batch|
      puts "Processing batch starting with id=#{batch.first.id}"

      batch.each do |u|
        next if u.user_pass.present?

        attempts = 0
        loop do
          candidate = User.generate_user_pass

          begin
            # Use update_column to avoid validations/callbacks; uniqueness enforced by DB index
            u.update_column(:user_pass, candidate)
            break
          rescue ActiveRecord::RecordNotUnique
            attempts += 1
            if attempts >= 10
              fallback = "#{User.generate_user_pass}#{SecureRandom.random_number(90) + 10}"
              u.update_column(:user_pass, fallback)
              break
            end
            # retry with a new candidate
          end
        end
      end
    end

    puts 'Finished user_pass backfill'
  end
end
