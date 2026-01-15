package backup

import (
	"fmt"
	"log"
	"os"
	"os/exec"
	"path/filepath"
	"time"
)

func PerformBackup() (string, error) {
	filename := fmt.Sprintf("backup_%s.sql", time.Now().Format("2006-01-02_15-04-05"))
	absPath := filepath.Join("/root/backups", filename)

	if err := os.MkdirAll("/root/backups", 0777); err != nil {
		return "", fmt.Errorf("failed to create directory: %v", err)
	}

	outFile, err := os.Create(absPath)
	if err != nil {
		return "", fmt.Errorf("failed to create file: %v", err)
	}
	defer outFile.Close()

	pgPwd := os.Getenv("POSTGRES_PASSWORD")
	pgHost := os.Getenv("DB_HOST")
	pgUser := os.Getenv("POSTGRES_USER")
	pgDb := os.Getenv("POSTGRES_DB")

	cmd := exec.Command("pg_dump", "-h", pgHost, "-U", pgUser, "-d", pgDb)

	cmd.Env = append(os.Environ(), 
        fmt.Sprintf("PGPASSWORD=%s", pgPwd),
        "PGSSLMODE=disable",
    )

	cmd.Stdout = outFile
	cmd.Stderr = os.Stderr 

	log.Printf("Starting pg_dump to file: %s", absPath)

	if err := cmd.Run(); err != nil {
		return "", fmt.Errorf("pg_dump execution failed: %v", err)
	}

	info, err := outFile.Stat()
	if err != nil || info.Size() == 0 {
		return "", fmt.Errorf("backup file created but it is empty (0 bytes)")
	}

	log.Printf("Backup success. Size: %d bytes", info.Size())
	return filename, nil
}

func StartDailyBackupScheduler() {
	
	ticker := time.NewTicker(24 * time.Hour)
	
	go func() {
		for {
			select {
			case <-ticker.C:
				log.Println("Starting automatic daily backup...")
				_, err := PerformBackup()
				if err != nil {
					log.Printf("Auto-backup failed: %v", err)
				}
			}
		}
	}()
	
	log.Println("Daily backup scheduler started (every 24h)")
}