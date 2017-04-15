#
# Skrypt do automatycznego logowania się na 24.play.pl
# written by Grzegorz `antekone` Antoniak
#
# www: http://anadoxin.org/blog
# twitter: @antekone
# mastodon: @antekone@mstdn.io
#
# "Granted to the public domain"
#
# Sprawdza stan konta oraz weryfikuje istnienie usługi "30 dni bez limitu".
#
# W przypadku, gdy usługa nie jest aktywna, zostaje wysłany mail z
# przypomnieniem o potrzebie aktywacji.
#
# Aby uruchomić, potrzebne są:
#
# - ruby23
# - gem mechanize
# - gem nokogiri
# - gem json
# - plik ~/.playonline/credentials.json, przykładowa treść:
#
#   {
#     "username": "login_do_play24",
#     "password": "haslo_do_play24",
#     "recipient": "na ktory mail wysylac wiadomosc?"
#   }
#
# - wysyłanie maila odbywa się za pomocą programu mutt. Mutt tworzy wiadomość
#   i używa innego narzędzia do akcji smtp, to znaczy że aby wysyłanie emaili
#   działało poprawnie, trzeba skonfigurować mutt'a oraz np. msmtp.
#
#   chyba, że zmienisz funkcję send_mail_notification na swoją.
#
# - skrypt jest pisany na moje potrzeby więc prawdopodobnie nie będzie tobie
#   działał w idealny sposób, ale po to go udostępniam aby go sobie zmienić ;)
#
# - przykładowy setup: wrzucić do cron'a raz dziennie i skonfigurować wysyłanie
#   maili.
#
# - testowane tylko na openbsd 6.1.
#
# gl hf

require 'mechanize'
require 'nokogiri'
require 'json'

$stdprefix = "https://24.play.pl/Play24/dwr/call/plaincall"

$servicesdata=<<EOF
callCount=1
windowName=
nextReverseAjaxIndex=0
c0-scriptName=templateRemoteService
c0-methodName=view
c0-id=0
c0-param0=string:PACKAGES
batchId=0
instanceId=0
page=%2FPlay24%2FServices
scriptSessionId=KI2iv27OLhlwVIMZLOF9kzYZJJl/UBW5MJl-LnXgzTNUb
EOF

$balancedata=<<EOF
callCount=1
windowName=
nextReverseAjaxIndex=0
c0-scriptName=balanceRemoteService
c0-methodName=getBalances
c0-id=0
batchId=4
instanceId=0
page=%2FPlay24%2FWelcome
scriptSessionId=KI2iv27OLhlwVIMZLOF9kzYZJJl/UBW5MJl-LnXgzTNUb
EOF

begin
  contents = File.open("#{ENV['HOME']}/.playonline/credentials.json").read()
  $creds = JSON.parse(contents)
rescue Errno::ENOENT => e
  puts "Missing ~/.playonline/credentials.json file."
  exit 1
end

def send_mail_notification(subject, body)
  `echo "#{body}" | mutt #{$creds['recipient']} -s "[PLAYONLINE] #{subject}"`
end

def get_rpc_data(m, url, methodblob)
  ret = m.post(url, methodblob, 'Content-Type' => 'text/plain')
  body = ret.body
  mark1 = body.index(",view:\"")
  mark2 = body.index("\"}));")

  if mark1 == nil or mark2 == nil
    return nil
  else
    html = body[(mark1  + 7) .. (mark2 - 1)]
    return html
  end

  nil
end

def get_doc_from_json(html)
  json = '{"data": "' + html + '"}'
  html = JSON.parse(json)['data']
  Nokogiri::HTML(html)
end

def parse_service_status(service_html)
  html = service_html
  doc = get_doc_from_json(html)

  found = 0
  doc.xpath("//td").each() do |td|
    if found == 0
      if td.children[0].to_s.index("30 dni bez limitu") != nil
        found = 1
      end
    elsif found == 1
      if td.children[0].to_s.index("30,00") != nil
        found = 2;
      end
    elsif found == 2
      data = td.children[1].children[0].to_s.strip
      if data == "wyłączony"
        return "off"
      elsif data == "włączony"
        return "on"
      else
        return nil
      end
    end
  end

  nil
end

def parse_balance(balance_html)
  doc = get_doc_from_json(balance_html)
  doc.css(".font-add")[1].children[0].children[0].to_s.strip
end

def get_service_status()
  service_html = nil
  balance_html = nil

  m = Mechanize.new()
  m.verify_mode = OpenSSL::SSL::VERIFY_NONE
  m.get("http://24.play.pl") { |page|
    form = page.forms[0]
    loginpage = form.submit
    form = loginpage.forms[0]
    form.field_with(:name => "IDToken1").value = $creds['username']
    form.field_with(:name => "IDToken2").value = $creds['password']
    panelpage = form.submit
    panelpage.forms[0].submit

    # w przypadku złego loginu kolejne funkcje zgłoszą error ;P

    url = "#{$stdprefix}/templateRemoteService.view.dwr"
    service_html = get_rpc_data(m, url, $servicesdata)
    if service_html == nil
      return { 'status' => 'error',
               'error' => 'cant proces templateRemoteService' }
    end

    url = "#{$stdprefix}/balanceRemoteService.getBalances.dwr"
    balance_html = get_rpc_data(m, url, $balancedata)
    if balance_html == nil
      return { 'status' => 'error',
               'error' => 'cant process balanceRemoteService.getBalances' }
    end
  }

  service_info = parse_service_status(service_html)
  balance_info = parse_balance(balance_html)

  return { 'error' => 'service_info is nil' } if service_info == nil
  return { 'error' => 'balance_info is nil' } if balance_info == nil

  return { 'status' => service_info,
           'balance' => balance_info }
end

def main()
  status = get_service_status()
  if status.key? "error" or not status.key? "status"
    send_mail_notification(
      "Skrypt się nie powiódł",

      "Coś poszło nie tak ;(")
  else
    if status['status'] == 'off'
      send_mail_notification(
        "Usługa jest wyłączona",

        "Włącz usługę, bo jest wyłączona!\n\n" \
        "Stan konta: #{status['balance']} zł")
    end
  end
end

main
