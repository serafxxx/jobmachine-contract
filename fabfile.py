from invoke import task
from fabric import Connection, Config
import os.path
import re

AC = "0xf39fd6e51aad88f6f4ce6ab8827279cfffb92266"
PK = "ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"
RPC = "http://127.0.0.1:8545"
CONTRACT = "src/JobMachine.sol:JobMachine"

@task
def build(c):
    c.run("forge build")

@task
def test(c):
    c.run("forge test")

@task
def anvil(c):
    c.run("anvil")

@task
def test(c):
    c.run("forge test")

@task
def balance(c):
	res = c.run(f"cast balance {AC}")
	wei = int(res.stdout)
	print(f"{wei/1000000000000000000} ETH")

@task
def create(c):
	cmd = f"forge create --rpc-url {RPC} --private-key {PK} {CONTRACT}"
	print("\n",cmd)
	res = c.run(cmd)
	deployed_to = re.search("Deployed to: (0x\w{40})", res.stdout).group(1)
	return deployed_to

@task
def call(c, where, what):
	cmd = f"cast call --rpc-url {RPC} {where} \"{what}\""
	print("\n",cmd)
	res = c.run(cmd)

@task
def send(c, where, what, what2):
	cmd = f"cast send --rpc-url {RPC} --private-key {PK} {where} \"{what}\" {what2}"
	print("\n",cmd)
	res = c.run(cmd)

@task
def init(c):
	deployed_to = create(c)
	send(c, deployed_to, "setJobMintFee(uint)", 14)
	call(c, deployed_to, "jobMintFee()(uint)")

