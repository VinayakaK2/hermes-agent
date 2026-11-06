import os
import sys
import shutil
import tarfile
from pathlib import Path

HF_TOKEN = os.getenv("HF_TOKEN")
HF_DATASET_ID = os.getenv("HF_DATASET_ID", "VinayakaK/hermes-storage")
DATA_DIR = Path(os.getenv("HERMES_HOME", "/opt/data"))
DB_PATH = DATA_DIR / "state.db"
SKILLS_DIR = DATA_DIR / "skills"
CONFIG_PATH = DATA_DIR / "config.yaml"

def get_api():
    if not HF_TOKEN:
        print("[HF-Sync] Warning: HF_TOKEN is not set. Cloud storage disabled.")
        return None
    from huggingface_hub import HfApi
    return HfApi(token=HF_TOKEN)

def download_data():
    api = get_api()
    if not api:
        return

    DATA_DIR.mkdir(parents=True, exist_ok=True)
    from huggingface_hub import hf_hub_download
    from huggingface_hub.utils import HfHubHTTPError

    try:
        api.dataset_info(HF_DATASET_ID)
    except Exception as e:
        print(f"[HF-Sync] Dataset {HF_DATASET_ID} not found or inaccessible: {e}")
        try:
            print(f"[HF-Sync] Attempting to create private dataset {HF_DATASET_ID}...")
            api.create_repo(repo_id=HF_DATASET_ID, repo_type="dataset", private=True, exist_ok=True)
            print(f"[HF-Sync] Dataset {HF_DATASET_ID} created successfully.")
        except Exception as create_err:
            print(f"[HF-Sync] Could not create dataset: {create_err}")
        return

    # 1. Download state.db
    try:
        print(f"[HF-Sync] Downloading state.db from {HF_DATASET_ID}...")
        downloaded = hf_hub_download(
            repo_id=HF_DATASET_ID,
            filename="state.db",
            repo_type="dataset",
            token=HF_TOKEN
        )
        if downloaded and os.path.exists(downloaded):
            shutil.copyfile(downloaded, str(DB_PATH))
            os.chmod(str(DB_PATH), 0o666)
            print(f"[HF-Sync] state.db restored successfully to {DB_PATH}")
    except HfHubHTTPError as e:
        if e.response.status_code == 404:
            print("[HF-Sync] No existing state.db in dataset (new deployment).")
        else:
            print(f"[HF-Sync] HTTP error downloading state.db: {e}")
    except Exception as e:
        print(f"[HF-Sync] Error downloading state.db: {e}")

    # 2. Download skills archive
    try:
        downloaded_skills = hf_hub_download(
            repo_id=HF_DATASET_ID,
            filename="skills.tar.gz",
            repo_type="dataset",
            token=HF_TOKEN
        )
        if downloaded_skills and os.path.exists(downloaded_skills):
            SKILLS_DIR.mkdir(parents=True, exist_ok=True)
            with tarfile.open(downloaded_skills, "r:gz") as tar:
                tar.extractall(path=str(DATA_DIR))
            print(f"[HF-Sync] skills restored successfully to {SKILLS_DIR}")
    except Exception:
        pass

    # 3. Download config.yaml if exists
    try:
        downloaded_cfg = hf_hub_download(
            repo_id=HF_DATASET_ID,
            filename="config.yaml",
            repo_type="dataset",
            token=HF_TOKEN
        )
        if downloaded_cfg and os.path.exists(downloaded_cfg):
            shutil.copyfile(downloaded_cfg, str(CONFIG_PATH))
            os.chmod(str(CONFIG_PATH), 0o666)
            print(f"[HF-Sync] config.yaml restored successfully to {CONFIG_PATH}")
    except Exception:
        pass

def upload_data():
    api = get_api()
    if not api:
        return

    # 1. Upload state.db
    if DB_PATH.exists() and DB_PATH.stat().st_size > 0:
        tmp_db = Path("/tmp/state_backup.db")
        try:
            shutil.copy2(str(DB_PATH), str(tmp_db))
            print(f"[HF-Sync] Uploading state.db ({tmp_db.stat().st_size} bytes)...")
            api.upload_file(
                path_or_fileobj=str(tmp_db),
                path_in_repo="state.db",
                repo_id=HF_DATASET_ID,
                repo_type="dataset",
                commit_message="Automated state.db backup from Render"
            )
            print("[HF-Sync] state.db uploaded successfully.")
        except Exception as e:
            print(f"[HF-Sync] Failed to upload state.db: {e}")
        finally:
            if tmp_db.exists():
                try:
                    tmp_db.unlink()
                except OSError:
                    pass

    # 2. Upload skills if present
    if SKILLS_DIR.exists() and any(SKILLS_DIR.iterdir()):
        tmp_tar = Path("/tmp/skills_backup.tar.gz")
        try:
            with tarfile.open(str(tmp_tar), "w:gz") as tar:
                tar.add(str(SKILLS_DIR), arcname="skills")
            api.upload_file(
                path_or_fileobj=str(tmp_tar),
                path_in_repo="skills.tar.gz",
                repo_id=HF_DATASET_ID,
                repo_type="dataset",
                commit_message="Automated skills backup from Render"
            )
            print("[HF-Sync] skills uploaded successfully.")
        except Exception as e:
            print(f"[HF-Sync] Failed to upload skills: {e}")
        finally:
            if tmp_tar.exists():
                try:
                    tmp_tar.unlink()
                except OSError:
                    pass

    # 3. Upload config.yaml if present
    if CONFIG_PATH.exists() and CONFIG_PATH.stat().st_size > 0:
        try:
            api.upload_file(
                path_or_fileobj=str(CONFIG_PATH),
                path_in_repo="config.yaml",
                repo_id=HF_DATASET_ID,
                repo_type="dataset",
                commit_message="Automated config.yaml backup from Render"
            )
        except Exception as e:
            print(f"[HF-Sync] Failed to upload config.yaml: {e}")

if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "upload":
        upload_data()
    else:
        download_data()
