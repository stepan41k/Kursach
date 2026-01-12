package mail

import (
	"fmt"
	"log"
	"net/smtp"
	"os"
	"time"
)

func SendLoginEmail(toEmail string, userName string, ip string) {
	host := os.Getenv("SMTP_HOST")
	port := os.Getenv("SMTP_PORT")
	user := os.Getenv("SMTP_USER")
	pass := os.Getenv("SMTP_PASS")
	from := os.Getenv("SMTP_FROM")

	if host == "" || toEmail == "" {
		return
	}

	headers := fmt.Sprintf("From: %s\r\n", from) +
		fmt.Sprintf("To: %s\r\n", toEmail) +
		"Subject: Оповещение о входе в RoseBank\r\n" +
		"MIME-version: 1.0;\r\n" +
		"Content-Type: text/plain; charset=\"UTF-8\";\r\n\r\n"

	body := fmt.Sprintf("Здравствуйте, %s!\n\nБыл выполнен вход в ваш аккаунт.\nВремя: %s\nIP-адрес: %s\n\nЕсли это были не вы, срочно обратитесь к администратору.",
		userName, time.Now().Format("02.01.2006 15:04"), ip)

	msg := []byte(headers + body)

	auth := smtp.PlainAuth("", user, pass, host)
	addr := fmt.Sprintf("%s:%s", host, port)
	
	err := smtp.SendMail(addr, auth, user, []string{toEmail}, msg)

	if err != nil {
		log.Printf("Failed to send login email to %s: %v", toEmail, err)
	} else {
		log.Printf("Login notification sent to %s", toEmail)
	}
}


func SendClientWelcomeEmail(toEmail string, fullName string, login string, password string) {
	host := os.Getenv("SMTP_HOST")
	port := os.Getenv("SMTP_PORT")
	user := os.Getenv("SMTP_USER") 
	pass := os.Getenv("SMTP_PASS")
	from := os.Getenv("SMTP_FROM")

	if host == "" || toEmail == "" {
		log.Println("SMTP not configured or email empty")
		return
	}

	headers := fmt.Sprintf("From: %s\r\n", from) +
		fmt.Sprintf("To: %s\r\n", toEmail) +
		"Subject: Добро пожаловать в RoseBank!\r\n" +
		"MIME-version: 1.0;\r\n" +
		"Content-Type: text/plain; charset=\"UTF-8\";\r\n\r\n"

	body := fmt.Sprintf(
		"Здравствуйте, %s!\n\n"+
			"Вы были успешно зарегистрированы в системе RoseBank.\n"+
			"Для входа в Личный кабинет клиента используйте следующие данные:\n\n"+
			"Логин: %s\n"+
			"Пароль: %s\n\n"+
			"Пожалуйста, никому не сообщайте свой пароль.",
		fullName, login, password,
	)

	msg := []byte(headers + body)
	addr := fmt.Sprintf("%s:%s", host, port)
	auth := smtp.PlainAuth("", user, pass, host)

	err := smtp.SendMail(addr, auth, user, []string{toEmail}, msg)
	
	if err != nil {
		log.Printf("Failed to send welcome email to %s: %v", toEmail, err)
	} else {
		log.Printf("Welcome email sent to %s", toEmail)
	}
}