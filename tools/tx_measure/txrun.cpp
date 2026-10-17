// Run a Machinedrum TX user machine (decoded MDS1 blob) in the dsp56kEmu
// interpreter: init, set params, trigger, render N blocks of 32 samples.
// Writes the output as float32 little-endian to stdout.
//
// usage: txrun blob.bin blocks p1 p2 ... p7   (params 0..127, in MDM1 order)
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>

#include "dsp56kEmu/assembler.h"
#include "dsp56kEmu/dsp.h"
#include "dsp56kEmu/memory.h"

#include "dsp56kEmu/peripherals.h"

using namespace dsp56k;
static DefaultMemoryValidator g_defaultMemoryValidator;

static const TWord STATE = 0x2000, OUTBUF = 0x3000, DRIVER = 0x7f00;

static void call(DSP& dsp, Memory& mem, const Assembler& as, TWord entry)
{
	char buf[64];
	TWord pc = DRIVER;
	const char* lines[4];
	std::string l0 = "move #>$2000,r6", l1 = "move #>$3000,r7";
	snprintf(buf, sizeof buf, "jsr $%x", entry);
	std::string l2 = buf;
	lines[0] = l0.c_str(); lines[1] = l1.c_str(); lines[2] = l2.c_str();
	for (int m = 0; m < 8; ++m)
	{
		char mb[32]; snprintf(mb, sizeof mb, m == 7 ? "move #>$1f,m%d" : "move #>$ffffff,m%d", m);
		auto rm = as.assemble(mb);
		if (!rm.success()) { fprintf(stderr, "asm failed: %s\n", mb); exit(1); }
		for (TWord w = 0; w < rm.wordCount; ++w) mem.set(MemArea_P, pc++, rm.word[w]);
	}
	for (int i = 0; i < 3; ++i)
	{
		auto r = as.assemble(lines[i]);
		if (!r.success()) { fprintf(stderr, "asm failed: %s\n", lines[i]); exit(1); }
		for (TWord w = 0; w < r.wordCount; ++w) mem.set(MemArea_P, pc++, r.word[w]);
	}
	const TWord done = pc;
	snprintf(buf, sizeof buf, "jmp >$%x", done);
	auto r = as.assemble(buf);
	for (TWord w = 0; w < r.wordCount; ++w) mem.set(MemArea_P, pc++, r.word[w]);
	dsp.clearOpcodeCache();
	dsp.setPC(DRIVER);
	for (long n = 0; n < 5000000; ++n)
	{
		dsp.execInterpreter();
		if (dsp.getPC().toWord() == done) return;
	}
	fprintf(stderr, "timeout in entry %x (pc %x)\n", entry, dsp.getPC().toWord());
	exit(1);
}

int main(int argc, char** argv)
{
	if (argc < 3) { fprintf(stderr, "usage: txrun blob blocks p1..p7\n"); return 1; }
	FILE* f = fopen(argv[1], "rb");
	std::vector<uint8_t> b;
	int c;
	while ((c = fgetc(f)) != EOF) b.push_back((uint8_t)c);
	fclose(f);
	auto be = [&](size_t o, int n) { uint32_t v = 0; for (int i = 0; i < n; ++i) v = (v << 8) | b[o + i]; return v; };
	const uint32_t nwords = be(0x14, 4);
	const TWord eInit = be(0x40, 2), eTrig = be(0x42, 2), eRender = be(0x44, 2);
	const int blocks = atoi(argv[2]);

	// MDM1: param records of 8 bytes (name[4], default, ?, max, flags) at +0x40
	size_t mdm = 0;
	for (size_t i = 0; i + 4 < b.size(); ++i) if (!memcmp(&b[i], "MDM1", 4)) { mdm = i; break; }

	PeripheralsNop px, py;
	Memory mem(g_defaultMemoryValidator, 0x10000);
	DSP dsp(mem, &px, &py);
	dsp.resetHW();
	for (uint32_t i = 0; i < nwords; ++i)
	{
		const TWord w = be(0x80 + 3 * i, 3);
		mem.set(MemArea_P, i, w);
		mem.set(MemArea_X, i, w);
	}
	for (TWord a = 0; a < 0x100; ++a) { mem.set(MemArea_X, STATE + a, 0); mem.set(MemArea_Y, STATE + a, 0); }
	Assembler as;

	call(dsp, mem, as, eInit);
	for (int k = 0; k < 7; ++k)
	{
		const size_t rec = mdm + 0x40 + 8 * k;
		const int flags = b[rec + 7];
		int p = argc > 3 + k ? atoi(argv[3 + k]) : b[rec + 4];
		const TWord v = (flags & 1) ? (TWord)(p << 16) : (flags & 2) ? (TWord)p : (TWord)(p << 7);
		mem.set(MemArea_Y, STATE + 1 + k, v);
	}
	call(dsp, mem, as, eTrig);
	std::vector<float> out;
	for (int n = 0; n < blocks; ++n)
	{
		call(dsp, mem, as, eRender);
		if (getenv("TXDUMPX")) { const TWord a = STATE + (TWord)strtoul(getenv("TXDUMPX"), nullptr, 0); int32_t v = (int32_t)(mem.get(MemArea_X, a) << 8) >> 8; int32_t e = (int32_t)(mem.get(MemArea_X, STATE + 0x13) << 8) >> 8; fprintf(stderr, "%d %.6f %.6f\n", n, v / 8388608.0, e / 8388608.0); }
		for (TWord i = 0; i < (getenv("TXW") ? (TWord)atoi(getenv("TXW")) : 32); ++i)
		{
			int32_t s = (int32_t)(mem.get(MemArea_Y, OUTBUF + i) << 8) >> 8;
			out.push_back(s / 8388608.0f);
		}
	}
	FILE* o = fopen(getenv("TXOUT"), "wb"); fwrite(out.data(), sizeof(float), out.size(), o); fclose(o);
	return 0;
}
