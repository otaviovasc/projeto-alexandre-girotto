namespace :web_push do
  desc 'Gera chaves VAPID para notificações Web Push'
  task vapid_keys: :environment do
    key = WebPush.generate_key

    puts "WEB_PUSH_PUBLIC_KEY=#{key.public_key}"
    puts "WEB_PUSH_PRIVATE_KEY=#{key.private_key}"
    puts 'WEB_PUSH_SUBJECT=mailto:contato@villaggiogirotto.com.br'
  end
end
