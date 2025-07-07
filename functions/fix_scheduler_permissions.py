#!/usr/bin/env python3
"""
修复Cloud Scheduler权限的脚本
这个脚本帮助诊断和修复Cloud Functions定时任务不执行的问题
"""

import subprocess
import sys
import json

def run_command(cmd):
    """执行命令并返回结果"""
    try:
        result = subprocess.run(cmd, shell=True, capture_output=True, text=True)
        return result.returncode == 0, result.stdout, result.stderr
    except Exception as e:
        return False, "", str(e)

def check_project_info():
    """检查项目信息"""
    print("🔍 检查项目信息...")
    success, stdout, stderr = run_command("gcloud config get-value project")
    if success:
        project_id = stdout.strip()
        print(f"✅ 当前项目: {project_id}")
        return project_id
    else:
        print("❌ 无法获取项目信息，请确保已安装并配置gcloud CLI")
        return None

def check_scheduler_jobs():
    """检查Cloud Scheduler作业"""
    print("\n🔍 检查Cloud Scheduler作业...")
    success, stdout, stderr = run_command("gcloud scheduler jobs list --location=us-central1 --format=json")
    
    if success:
        try:
            jobs = json.loads(stdout) if stdout.strip() else []
            print(f"📋 找到 {len(jobs)} 个Scheduler作业:")
            for job in jobs:
                name = job.get('name', '').split('/')[-1]
                state = job.get('state', 'UNKNOWN')
                schedule = job.get('schedule', 'N/A')
                print(f"  • {name}: {state} ({schedule})")
            return jobs
        except json.JSONDecodeError:
            print("❌ 解析Scheduler作业列表失败")
    else:
        print(f"❌ 获取Scheduler作业失败: {stderr}")
    
    return []

def check_function_invoker_permissions():
    """检查Cloud Functions的调用权限"""
    print("\n🔍 检查Cloud Functions调用权限...")
    
    functions = ['daily_metrics_aggregation', 'test_scheduler']
    
    for func_name in functions:
        print(f"\n检查函数: {func_name}")
        
        # 获取函数的IAM策略
        cmd = f"gcloud functions get-iam-policy {func_name} --region=us-central1 --format=json"
        success, stdout, stderr = run_command(cmd)
        
        if success:
            try:
                policy = json.loads(stdout) if stdout.strip() else {"bindings": []}
                
                # 查找 Cloud Scheduler 服务账户
                scheduler_binding = None
                for binding in policy.get('bindings', []):
                    if binding.get('role') == 'roles/cloudfunctions.invoker':
                        members = binding.get('members', [])
                        scheduler_members = [m for m in members if 'service-' in m and 'cloudscheduler' in m]
                        if scheduler_members:
                            scheduler_binding = binding
                            break
                
                if scheduler_binding:
                    print(f"  ✅ {func_name} 有正确的调用权限")
                else:
                    print(f"  ❌ {func_name} 缺少Cloud Scheduler调用权限")
                    
            except json.JSONDecodeError:
                print(f"  ❌ 解析{func_name}的IAM策略失败")
        else:
            print(f"  ❌ 获取{func_name}的IAM策略失败: {stderr}")

def fix_permissions():
    """修复权限问题"""
    print("\n🔧 尝试修复权限...")
    
    # 获取项目编号
    success, stdout, stderr = run_command("gcloud projects describe $(gcloud config get-value project) --format='value(projectNumber)'")
    if not success:
        print("❌ 无法获取项目编号")
        return False
    
    project_number = stdout.strip()
    scheduler_sa = f"service-{project_number}@gcp-sa-cloudscheduler.iam.gserviceaccount.com"
    
    print(f"📧 Cloud Scheduler服务账户: {scheduler_sa}")
    
    functions = ['daily_metrics_aggregation', 'test_scheduler']
    
    for func_name in functions:
        print(f"\n为函数 {func_name} 添加调用权限...")
        
        cmd = f"gcloud functions add-iam-policy-binding {func_name} --region=us-central1 --member='serviceAccount:{scheduler_sa}' --role='roles/cloudfunctions.invoker'"
        
        success, stdout, stderr = run_command(cmd)
        
        if success:
            print(f"  ✅ {func_name} 权限添加成功")
        else:
            print(f"  ⚠️ {func_name} 权限添加失败 (可能已存在): {stderr}")
    
    return True

def main():
    """主函数"""
    print("🚀 Cloud Scheduler权限诊断和修复工具")
    print("=" * 50)
    
    # 检查项目
    project_id = check_project_info()
    if not project_id:
        return
    
    # 检查Scheduler作业
    jobs = check_scheduler_jobs()
    
    # 检查权限
    check_function_invoker_permissions()
    
    # 询问是否修复权限
    print("\n" + "=" * 50)
    choice = input("🔧 是否尝试自动修复权限问题? (y/N): ").strip().lower()
    
    if choice in ['y', 'yes']:
        fix_permissions()
        print("\n✅ 权限修复完成！请等待5-10分钟后检查函数日志。")
    else:
        print("\n📋 手动修复步骤:")
        print("1. 访问 Google Cloud Console")
        print("2. 进入 Cloud Functions → 选择函数 → 权限选项卡")
        print("3. 添加 Cloud Scheduler 服务账户为 'Cloud Functions Invoker'")
    
    print("\n🔍 检查建议:")
    print("• 等待5-10分钟后运行: firebase functions:log --only test_scheduler")
    print("• 查看Firestore中的test_scheduler集合是否有新记录")
    print("• 如果测试定时器正常，每日聚合也会正常工作")

if __name__ == "__main__":
    main() 