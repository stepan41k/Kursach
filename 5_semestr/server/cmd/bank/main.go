package main

import (
	"context"
	"log"
	"os"
	"time"

	"github.com/gin-contrib/cors"
	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/stepan41k/Kursach/5_semestr/pkg/backup"
	"github.com/stepan41k/Kursach/5_semestr/pkg/handler"
	"github.com/stepan41k/Kursach/5_semestr/pkg/lib/auth"
)

func initDB() (*pgxpool.Pool) {
	dbUrl := os.Getenv("DATABASE_URL")

	if dbUrl == "" {
		log.Fatal("DATABASE_URL environment variable is not set")
	}

	config, err := pgxpool.ParseConfig(dbUrl)
	if err != nil {
		log.Fatal("Unable to parse DB URL:", err)
	}

	db, err := pgxpool.NewWithConfig(context.Background(), config)
	if err != nil {
		log.Fatal("Unable to connect to database:", err)
	}

	// Проверка связи
	if err := db.Ping(context.Background()); err != nil {
		log.Fatal("Database ping failed:", err)
	}
	log.Println("Connected to PostgreSQL via pgxpool")

	return db
}


func main() {
	db := initDB()

	defer db.Close()

	driver := handler.NewHandlerDriver(db)

	backup.StartDailyBackupScheduler()

	r := gin.Default()
	r.Use(cors.New(cors.Config{
			AllowOrigins:     []string{"http://localhost:3010"}, // Разрешаем всем (или укажите "http://localhost:3010")
			AllowMethods:     []string{"GET", "POST", "PUT", "DELETE", "OPTIONS"},
			AllowHeaders:     []string{"Origin", "Content-Type", "Authorization"},
			ExposeHeaders:    []string{"Content-Length"},
			AllowCredentials: true,
			MaxAge:           12 * time.Hour,
		}))

	api := r.Group("/api")
	{
		api.POST("/login", driver.LoginHandler)
		
		protected := api.Group("/")
		protected.Use(auth.AuthMiddleware())
		{
			protected.POST("/register", driver.RegisterHandler)
			protected.GET("/clients", driver.GetClients)
			protected.POST("/clients", driver.CreateClient)
			protected.GET("/products", driver.GetProducts)
			protected.POST("/loans", driver.IssueLoan)
			protected.GET("/loans", driver.GetLoans)
			protected.GET("/loans/:id/schedule", driver.GetSchedule)
			protected.GET("/employees", driver.GetEmployeesHandler)
			protected.GET("/logs", driver.GetLogsHandler)

			protected.POST("/backup", driver.CreateBackupHandler)

    		protected.GET("/my-loans", driver.GetMyLoansHandler)

			protected.POST("/pay", driver.MakePaymentHandler)
		}
		
	}

	r.Run(":8080")
}