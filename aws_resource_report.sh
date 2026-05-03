#!/bin/bash

# ================================================================
# aws_resource_report.sh
#
# Purpose  : Collect and report AWS resource usage daily
# Schedule : Cron — every day at 20:00
# Auth     : IAM Role attached to EC2 (preferred) or aws configure
# Output   : /home/ubuntu/aws-reports/aws_report_YYYY-MM-DD.txt
# Tested on: Ubuntu 22.04 / AWS CLI v2
# ================================================================

set -euo pipefail

# ── Configuration ────────────────────────────────────────────────
REPORT_DIR="/home/ubuntu/aws-reports"
LOG_FILE="$REPORT_DIR/script.log"
DATE=$(date +"%Y-%m-%d")
TIME=$(date +"%H:%M:%S")
REPORT_FILE="\(REPORT_DIR/aws_report_\)DATE.txt"
REGION=$(aws configure get region 2>/dev/null || echo "us-east-1")

# Create report directory if it does not exist
mkdir -p "$REPORT_DIR"

# ── Logging Helper ───────────────────────────────────────────────
# tee -a writes to log file AND prints to terminal simultaneously
log() {
    echo "[\((date +"%Y-%m-%d %H:%M:%S")]  \)1" | tee -a "$LOG_FILE"
}

# ── Section Header Helper ────────────────────────────────────────
# $1 = section title passed as argument
print_section() {
    {
        echo ""
        echo "============================================"
        echo "  $1"
        echo "============================================"
    } >> "$REPORT_FILE"
}

# ── Report Header ────────────────────────────────────────────────
log "Starting AWS resource report..."

# > creates fresh file (overwrites previous run if same day)
{
    echo "============================================"
    echo "   AWS DAILY RESOURCE USAGE REPORT"
    echo "   Date   : $DATE"
    echo "   Time   : $TIME"
    echo "   Region : $REGION"
    echo "============================================"
} > "$REPORT_FILE"

# ── Section 1: EC2 Instances ─────────────────────────────────────
log "Collecting EC2 data..."
print_section "EC2 INSTANCES"

aws ec2 describe-instances \
    --region "$REGION" \
    --query 'Reservations[*].Instances[*].[
        InstanceId,
        InstanceType,
        State.Name,
        PublicIpAddress,
        Tags[?Key==`Name`].Value|[0]
    ]' \
    --output table >> "$REPORT_FILE" 2>&1

# Count instances separately (avoids polluting table output)
TOTAL_EC2=$(aws ec2 describe-instances \
    --region "$REGION" \
    --query 'Reservations[*].Instances[*].InstanceId' \
    --output text 2>/dev/null | wc -w)
echo "Total EC2 Instances: \(TOTAL_EC2" >> "\)REPORT_FILE"

# ── Section 2: S3 Buckets ────────────────────────────────────────
log "Collecting S3 data..."
print_section "S3 BUCKETS"

aws s3 ls >> "$REPORT_FILE" 2>&1
TOTAL_S3=$(aws s3 ls 2>/dev/null | wc -l)
echo "Total S3 Buckets: \(TOTAL_S3" >> "\)REPORT_FILE"

# ── Section 3: IAM Users ─────────────────────────────────────────
log "Collecting IAM data..."
print_section "IAM USERS"

aws iam list-users \
    --query 'Users[*].[UserName, CreateDate, PasswordLastUsed]' \
    --output table >> "$REPORT_FILE" 2>&1

TOTAL_IAM=$(aws iam list-users \
    --query 'Users[*].UserName' \
    --output text 2>/dev/null | wc -w)
echo "Total IAM Users: \(TOTAL_IAM" >> "\)REPORT_FILE"

# ── Section 4: RDS Instances ─────────────────────────────────────
log "Collecting RDS data..."
print_section "RDS INSTANCES"

aws rds describe-db-instances \
    --region "$REGION" \
    --query 'DBInstances[*].[
        DBInstanceIdentifier,
        Engine,
        EngineVersion,
        DBInstanceStatus,
        DBInstanceClass
    ]' \
    --output table >> "$REPORT_FILE" 2>&1

TOTAL_RDS=$(aws rds describe-db-instances \
    --region "$REGION" \
    --query 'DBInstances[*].DBInstanceIdentifier' \
    --output text 2>/dev/null | wc -w)
echo "Total RDS Instances: \(TOTAL_RDS" >> "\)REPORT_FILE"

# ── Section 5: Elastic IPs ───────────────────────────────────────
log "Collecting Elastic IP data..."
print_section "ELASTIC IPs"

aws ec2 describe-addresses \
    --region "$REGION" \
    --query 'Addresses[*].[PublicIp, InstanceId, AllocationId, AssociationId]' \
    --output table >> "$REPORT_FILE" 2>&1

# ── Section 6: Security Groups ───────────────────────────────────
log "Collecting Security Group data..."
print_section "SECURITY GROUPS"

aws ec2 describe-security-groups \
    --region "$REGION" \
    --query 'SecurityGroups[*].[GroupName, GroupId, VpcId, Description]' \
    --output table >> "$REPORT_FILE" 2>&1

# ── Summary ──────────────────────────────────────────────────────
print_section "RESOURCE SUMMARY"

{
    echo "Resource               | Count"
    echo "----------------------------"
    echo "EC2 Instances          | $TOTAL_EC2"
    echo "S3 Buckets             | $TOTAL_S3"
    echo "IAM Users              | $TOTAL_IAM"
    echo "RDS Instances          | $TOTAL_RDS"
    echo "----------------------------"
    echo "Report generated at    : $TIME"
    echo "Report saved to        : $REPORT_FILE"
    echo "============================================"
} >> "$REPORT_FILE"

# ── Cleanup: Delete Reports Older Than 30 Days ───────────────────
find "$REPORT_DIR" -name "aws_report_*.txt" -mtime +30 -delete
log "Cleanup complete. Reports older than 30 days removed."

# ── Print to Terminal and Finish ─────────────────────────────────
cat "$REPORT_FILE"
log "Report generation complete. File: $REPORT_FILE"
