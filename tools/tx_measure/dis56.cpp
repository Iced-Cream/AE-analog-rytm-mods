// Minimal DSP56300 disassembler driver: reads big-endian 24-bit P words from a raw
// file and prints one line per instruction using dsp56kEmu's Disassembler.
#include <cstdio>
#include <cstdlib>
#include <string>
#include <vector>
#include "dsp56kEmu/disasm.h"
#include "dsp56kEmu/opcodes.h"

using namespace dsp56k;

int main(int argc, char** argv)
{
	if (argc < 2) { fprintf(stderr, "usage: dis56 words.bin [start] [count]\n"); return 1; }
	FILE* f = fopen(argv[1], "rb");
	if (!f) return 1;
	std::vector<uint8_t> raw;
	int c;
	while ((c = fgetc(f)) != EOF) raw.push_back((uint8_t)c);
	fclose(f);
	std::vector<TWord> w;
	for (size_t i = 0; i + 2 < raw.size(); i += 3)
		w.push_back((raw[i] << 16) | (raw[i + 1] << 8) | raw[i + 2]);
	TWord start = argc > 2 ? strtoul(argv[2], nullptr, 0) : 0;
	TWord count = argc > 3 ? strtoul(argv[3], nullptr, 0) : (TWord)w.size();
	Opcodes ops;
	Disassembler d(ops);
	for (TWord pc = start; pc < start + count && pc < w.size();)
	{
		std::string s;
		const TWord opB = pc + 1 < w.size() ? w[pc + 1] : 0;
		uint32_t len = d.disassemble(s, w[pc], opB, 0, 0, pc);
		if (len == 0) len = 1;
		printf("%04x: %06x%s %s\n", pc, w[pc], len > 1 ? " +" : "  ", s.c_str());
		pc += len;
	}
	return 0;
}
